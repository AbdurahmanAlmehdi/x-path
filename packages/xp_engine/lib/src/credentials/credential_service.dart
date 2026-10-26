import 'dart:async';
import 'dart:math';

import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/clock/clock.dart';
import 'package:xp_engine/src/credentials/credential_exceptions.dart';
import 'package:xp_engine/src/credentials/credential_material.dart';
import 'package:xp_engine/src/credentials/credential_record.dart';
import 'package:xp_engine/src/credentials/credential_repository.dart';
import 'package:xp_engine/src/credentials/credential_verifier.dart';
import 'package:xp_engine/src/git/github_client.dart';
import 'package:xp_engine/src/process/output_masker.dart';
import 'package:xp_engine/src/projects/project_exceptions.dart';
import 'package:xp_engine/src/projects/project_repository.dart';
import 'package:xp_engine/src/repositories/event_log.dart';
import 'package:xp_engine/src/secrets/secret_store.dart';
import 'package:xp_engine/src/tokens/device_token.dart';

/// The named credentials of the engine and the flavors that use them.
///
/// A credential has a name (unique regardless of case), a kind, a secret and
/// the result of its own check (does it authenticate). Any flavor of any
/// project may use it: a flavor uses at most one credential of each kind (an
/// assignment), and each assignment has its own check (can the credential
/// reach the flavor's bundle id, package or app). Preflight goes by both
/// (`credentials` guard check).
///
/// A credential is verified before it is stored: the store or tool it is for
/// must accept it, else nothing is written and the owner gets the reason and
/// what to do about it. Once stored it is checked again on request and by the
/// daily health check (`CredentialHealthCheck`).
///
/// Secrets live in the [SecretStore] only (D-07); nothing here or in the
/// events and errors contains one, and every secret value is handed to the
/// masker as soon as the engine knows it. The GitHub token is not a named
/// credential: the engine has one (`GitHubTokenService`).
///
/// Only `app` and `cli` tokens change credentials; changes and checks run one
/// at a time.
class CredentialService {
  /// Creates the service. [verifiers] holds one verifier per kind that can be
  /// checked.
  ///
  /// [random] is for tests; it must be cryptographically secure otherwise.
  new({
    required this._repository,
    required this._projects,
    required this._secrets,
    required Iterable<CredentialVerifier> verifiers,
    required this._masker,
    required this._events,
    required this._clock,
    Random? random,
  }) : _verifiers = {for (final verifier in verifiers) verifier.kind: verifier},
       _random = random ?? Random.secure();

  final CredentialRepository _repository;
  final ProjectRepository _projects;
  final SecretStore _secrets;
  final Map<CredentialKind, CredentialVerifier> _verifiers;
  final OutputMasker _masker;
  final EventLog _events;
  final Clock _clock;
  final Random _random;
  Future<void> _tail = Future.value();

  // ------------------------------------------------------------------ reads

  /// The named credentials, by name, with the flavors that use each.
  Future<List<NamedCredential>> list() async {
    final usages = <String, List<AssignedCredential>>{};
    for (final assignment in await _repository.assignments()) {
      (usages[assignment.id] ??= []).add(assignment);
    }
    return [
      for (final record in await _repository.list())
        record.toApi(usages[record.id] ?? const []),
    ];
  }

  /// The credential [id] with the flavors that use it.
  ///
  /// Throws a [CredentialNotFoundException].
  Future<NamedCredential> get(String id) async =>
      await _named(await _require(id));

  /// The credential each flavor of the project uses, by app, flavor and
  /// kind; only those of the app at [app] and the flavor [flavor] if given.
  ///
  /// Throws a [ProjectNotFoundException] if there is no such project, a
  /// [CredentialRequestException] for an [app] without a [flavor] and a
  /// [CredentialNotFoundException] if they name no flavor.
  Future<List<Credential>> listForProject(
    String projectId, {
    String? app,
    String? flavor,
  }) async {
    await _requireProject(projectId);
    if (flavor == null) {
      if (app != null) {
        throw const CredentialRequestException(
          '"app" needs a "flavor" with it.',
        );
      }
      return [
        for (final assignment in await _repository.assignments(
          projectId: projectId,
        ))
          assignment.toApi(),
      ];
    }
    final target = await _requireFlavor(projectId, app ?? '.', flavor);
    return [
      for (final assignment in await _repository.assignments(
        flavorId: target.id,
      ))
        assignment.toApi(),
    ];
  }

  // ----------------------------------------------------------------- writes

  /// Verifies the credential of [request] and, if it is accepted, stores it
  /// under its name. No flavor uses it yet.
  ///
  /// Throws a [CredentialForbiddenException] for a token kind [by] that may
  /// not, a [CredentialRequestException] for a malformed request or a
  /// `github` one, a [CredentialConflictException] if the name is taken, a
  /// [CredentialRejectedException] if the store or tool refused the
  /// credential, a [CredentialUnreachableException] if it could not be
  /// checked, and a [SecretStoreException] if the secrets cannot be written.
  /// Whatever is thrown, nothing is stored.
  Future<NamedCredential> create(
    CreateCredentialRequest request, {
    required DeviceToken by,
  }) => _serial(() async {
    requireOwner(by, 'add credentials');
    _requireNamedKind(request.kind);
    final name = _name(request.name);
    await _requireFreeName(name);
    final record = await _store(request.kind, name, request.material);
    return record.toApi();
  });

  /// Gives the credential [id] the name [name]. Its id, secret and
  /// assignments stay.
  ///
  /// Throws a [CredentialForbiddenException], a [CredentialNotFoundException],
  /// a [CredentialRequestException] for a name that cannot be one and a
  /// [CredentialConflictException] if another credential has it.
  Future<NamedCredential> rename(
    String id,
    String name, {
    required DeviceToken by,
  }) => _serial(() async {
    requireOwner(by, 'rename credentials');
    final record = await _require(id);
    final newName = _name(name);
    await _requireFreeName(newName, except: id);
    if (newName == record.name) return await _named(record);
    final renamed = record.renamed(newName);
    await _repository.save(renamed);
    _events.append(
      CredentialRenamed(credentialId: id, kind: record.kind, name: newName),
    );
    return await _named(renamed);
  });

  /// Verifies a new secret for the credential [id] and, if it is accepted,
  /// stores it in place of the old one. The id, the name and every
  /// assignment stay; the assignments are checked again with the new
  /// secret.
  ///
  /// Throws what [create] throws (but no conflict) and a
  /// [CredentialNotFoundException]. Whatever is thrown, nothing changes.
  Future<NamedCredential> replace(
    String id,
    ReplaceCredentialRequest request, {
    required DeviceToken by,
  }) => _serial(() async {
    requireOwner(by, 'replace the secret of credentials');
    final record = await _require(id);
    final material = CredentialMaterial.fromFields(
      record.kind,
      request.material,
    );
    _learn(material);
    final result = await _accept(material);
    await material.write(_secrets, record.secretKey);
    final updated = record.checked(
      status: CredentialStatus.verified,
      at: _clock.now(),
      account: result.account ?? material.account,
    );
    await _repository.save(updated);
    _events.append(
      CredentialSaved(
        credentialId: id,
        name: record.name,
        kind: record.kind,
        replaced: true,
      ),
    );
    for (final assignment in await _repository.assignments(credentialId: id)) {
      await _checkAssignment(assignment, material);
    }
    return await _named(updated);
  });

  /// Checks the credential [id] again (does it authenticate) and every
  /// assignment of it (can it reach the flavor's app), and keeps the
  /// results.
  ///
  /// Throws a [CredentialForbiddenException], a [CredentialNotFoundException]
  /// and a [SecretStoreException] if the secrets cannot be read.
  Future<NamedCredential> verify(String id, {required DeviceToken by}) =>
      _serial(() async {
        requireOwner(by, 'check credentials');
        return await _named(await _checkWithAssignments(await _require(id)));
      });

  /// Deletes the credential [id] and its secret (a secret another credential
  /// shares stays).
  ///
  /// A credential that flavors use is deleted only with [force]: they give it
  /// up first. Throws a [CredentialInUseException] with them otherwise, a
  /// [CredentialForbiddenException], a [CredentialNotFoundException] and a
  /// [SecretStoreException].
  Future<void> remove(
    String id, {
    required DeviceToken by,
    bool force = false,
  }) => _serial(() async {
    requireOwner(by, 'delete credentials');
    final record = await _require(id);
    final usages = await _repository.assignments(credentialId: id);
    if (usages.isNotEmpty && !force) {
      throw CredentialInUseException(
        '"${record.name}" is used by ${_places(usages)}. Delete it with force '
        'to remove it from them too.',
        [for (final usage in usages) usage.toUsage()],
      );
    }
    for (final usage in usages) {
      await _unassign(usage);
    }
    await _delete(record);
  });

  /// The flavor [flavor] of the app at [app] uses the credential of
  /// [request] for [kind] from now on, and, with
  /// [AssignCredentialRequest.allFlavors], every other flavor of the app too,
  /// except those that have another credential of [kind] when not
  /// [AssignCredentialRequest.replace]. Each assignment is checked at once
  /// and keeps the result; a refusal does not undo it.
  ///
  /// Throws a [CredentialForbiddenException], a [ProjectNotFoundException], a
  /// [CredentialNotFoundException] for an unknown flavor or credential, a
  /// [CredentialRequestException] for `github` or a credential of another
  /// kind, and a [SecretStoreException] if the secret cannot be read for the
  /// checks.
  Future<AssignCredentialResponse> assign(
    String projectId, {
    required String app,
    required String flavor,
    required CredentialKind kind,
    required AssignCredentialRequest request,
    required DeviceToken by,
  }) => _serial(() async {
    requireOwner(by, 'assign credentials');
    await _requireProject(projectId);
    _requireNamedKind(kind);
    final target = await _requireFlavor(projectId, app, flavor);
    final credential = await _require(request.credentialId);
    if (credential.kind != kind) {
      throw CredentialRequestException(
        '"${credential.name}" is a ${credential.kind.wire} credential, not '
        '${kind.wire}.',
      );
    }
    final flavors = request.allFlavors
        ? await _repository.flavorsOf(projectId, app)
        : [target];
    final assigned = <Credential>[];
    final kept = <Credential>[];
    CredentialMaterial? material;
    var loaded = false;
    for (final each in flavors) {
      final existing = await _repository.assignment(each.id, kind);
      final other = existing != null && existing.id != credential.id;
      if (other && each.id != target.id && !request.replace) {
        kept.add(existing.toApi());
        continue;
      }
      if (!loaded) {
        material = await _loadOrNull(credential);
        loaded = true;
      }
      final assignment = existing != null && !other
          ? existing
          : AssignedCredential(flavor: each, credential: credential);
      if (existing == null || other) {
        await _repository.assign(assignment);
        if (other) _announceUnassigned(existing);
        _events.append(
          CredentialAssigned(
            credentialId: credential.id,
            projectId: projectId,
            app: each.appPath,
            flavor: each.name,
            kind: kind,
          ),
        );
      }
      assigned.add((await _checkAssignment(assignment, material)).toApi());
    }
    return AssignCredentialResponse(assigned: assigned, kept: kept);
  });

  /// The flavor [flavor] of the app at [app] stops using its credential of
  /// [kind]. The credential stays.
  ///
  /// Throws a [CredentialForbiddenException], a [ProjectNotFoundException]
  /// and a [CredentialNotFoundException] if the flavor has none.
  Future<void> unassign(
    String projectId, {
    required String app,
    required String flavor,
    required CredentialKind kind,
    required DeviceToken by,
  }) => _serial(() async {
    requireOwner(by, 'unassign credentials');
    await _requireProject(projectId);
    final target = await _requireFlavor(projectId, app, flavor);
    final existing = await _repository.assignment(target.id, kind);
    if (existing == null) {
      throw CredentialNotFoundException(
        'The flavor "$flavor" of the app at "$app" has no ${kind.wire} '
        'credential.',
      );
    }
    await _unassign(existing);
  });

  // ------------------------------------------------- the deprecated routes

  /// What `PUT /projects/{id}/credentials` did before credentials had names:
  /// verifies the credential of [request] and makes the flavor use it.
  ///
  /// If the flavor's credential of the kind is used by this flavor alone, it
  /// gets the new secret (and the name of [request], if given). Otherwise a
  /// new credential is created, named as [request] says or after the kind
  /// and the flavor, and the flavor uses it; other flavors keep theirs. A
  /// `github` token becomes the engine's GitHub token. Returns the flavor's
  /// credential, and whether a credential was created.
  ///
  /// Throws what [create] and [assign] throw.
  Future<({Credential credential, bool created})> saveForFlavor(
    String projectId,
    SaveCredentialRequest request, {
    required DeviceToken by,
  }) => _serial(() async {
    requireOwner(by, 'save credentials');
    await _requireProject(projectId);
    final flavor = await _requireFlavor(projectId, request.app, request.flavor);
    if (request.kind == CredentialKind.github) {
      return (credential: await _saveGitHub(flavor, request), created: false);
    }
    final existing = await _repository.assignment(flavor.id, request.kind);
    final shared =
        existing != null &&
        (await _repository.assignments(credentialId: existing.id)).length > 1;
    final requested = request.name == null ? null : _name(request.name!);
    if (existing != null && !shared) {
      if (requested != null) {
        await _requireFreeName(requested, except: existing.id);
      }
      final material = CredentialMaterial.fromFields(
        request.kind,
        request.material,
      );
      _learn(material);
      final result = await _accept(material);
      await material.write(_secrets, existing.secretKey);
      var updated = existing.credential.checked(
        status: CredentialStatus.verified,
        at: _clock.now(),
        account: result.account ?? material.account,
      );
      if (requested != null && requested != updated.name) {
        updated = updated.renamed(requested);
      }
      await _repository.save(updated);
      _events.append(
        CredentialSaved(
          credentialId: updated.id,
          name: updated.name,
          projectId: projectId,
          kind: request.kind,
          replaced: true,
        ),
      );
      final checked = await _checkAssignment(
        existing.withCredential(updated),
        material,
      );
      return (credential: checked.toApi(), created: false);
    }
    final name = requested ?? await _generatedName(request.kind, flavor);
    await _requireFreeName(name);
    final record = await _store(
      request.kind,
      name,
      request.material,
      projectId: projectId,
    );
    final assignment = AssignedCredential(flavor: flavor, credential: record);
    await _repository.assign(assignment);
    if (existing != null) _announceUnassigned(existing);
    _events.append(
      CredentialAssigned(
        credentialId: record.id,
        projectId: projectId,
        app: flavor.appPath,
        flavor: flavor.name,
        kind: request.kind,
      ),
    );
    final material = await _loadOrNull(record);
    final checked = await _checkAssignment(assignment, material);
    return (credential: checked.toApi(), created: true);
  });

  /// What `POST /projects/{id}/credentials/{id}/verify` did: checks the
  /// credential and its assignments again, and returns it as the first
  /// flavor of the project that uses it sees it.
  ///
  /// Throws a [CredentialNotFoundException] if no flavor of the project uses
  /// it, besides what [verify] throws.
  Future<Credential> verifyInProject(
    String projectId,
    String credentialId, {
    required DeviceToken by,
  }) => _serial(() async {
    requireOwner(by, 'check credentials');
    await _requireProject(projectId);
    final record = await _require(credentialId);
    await _requireUsedIn(projectId, record);
    await _checkWithAssignments(record);
    final usages = await _repository.assignments(
      projectId: projectId,
      credentialId: credentialId,
    );
    return usages.first.toApi();
  });

  /// What `DELETE /projects/{id}/credentials/{id}` did: the flavors of the
  /// project give the credential up, and it is deleted with its secret if no
  /// other flavor uses it.
  ///
  /// Throws a [CredentialNotFoundException] if no flavor of the project uses
  /// it, besides what [remove] throws.
  Future<void> removeFromProject(
    String projectId,
    String credentialId, {
    required DeviceToken by,
  }) => _serial(() async {
    requireOwner(by, 'delete credentials');
    await _requireProject(projectId);
    final record = await _require(credentialId);
    for (final usage in await _requireUsedIn(projectId, record)) {
      await _unassign(usage);
    }
    if ((await _repository.assignments(credentialId: credentialId)).isEmpty) {
      await _delete(record, projectId: projectId);
    }
  });

  // ----------------------------------------------------------------- health

  /// Checks every credential and every assignment and keeps the results: the
  /// daily health check. Returns the credentials.
  ///
  /// Something that was accepted before and is refused now is announced as
  /// [CredentialExpired]. A credential whose check throws is left as it was,
  /// and the first such error is rethrown after the others were checked.
  ///
  /// Throws a [SecretsLockedException] at once if the secrets are locked.
  Future<List<NamedCredential>> checkAll() => _serial(() async {
    final checked = <NamedCredential>[];
    Object? failure;
    StackTrace? trace;
    for (final record in await _repository.list()) {
      try {
        checked.add(await _named(await _checkWithAssignments(record)));
      } on SecretsLockedException {
        rethrow;
      } on Object catch (error, stackTrace) {
        failure ??= error;
        trace ??= stackTrace;
      }
    }
    if (failure != null) Error.throwWithStackTrace(failure, trace!);
    return checked;
  });

  // ---------------------------------------------------------------- helpers

  /// Verifies [fields] as a credential of [kind] and stores it as [name].
  Future<CredentialRecord> _store(
    CredentialKind kind,
    String name,
    Map<String, dynamic> fields, {
    String? projectId,
  }) async {
    final material = CredentialMaterial.fromFields(kind, fields);
    _learn(material);
    final result = await _accept(material);
    final id = _newId();
    final secretKey = 'credential.$id';
    await material.write(_secrets, secretKey);
    final record =
        CredentialRecord(
          id: id,
          name: name,
          kind: kind,
          secretKey: secretKey,
        ).checked(
          status: CredentialStatus.verified,
          at: _clock.now(),
          account: result.account ?? material.account,
        );
    try {
      await _repository.save(record);
    } on Object {
      await CredentialMaterial.erase(kind, secretKey, _secrets);
      rethrow;
    }
    _events.append(
      CredentialSaved(
        credentialId: id,
        name: name,
        projectId: projectId,
        kind: kind,
        replaced: false,
      ),
    );
    return record;
  }

  /// Checks [material] as the credential check does, and throws unless it is
  /// accepted.
  Future<VerificationResult> _accept(CredentialMaterial material) async {
    final verifier = _verifiers[material.kind];
    if (verifier == null) {
      throw CredentialRejectedException(
        'This engine cannot check ${material.kind.wire} credentials yet.',
      );
    }
    final result = await verifier.verify(material, const CredentialTarget());
    switch (result.status) {
      case CredentialStatus.rejected:
        throw CredentialRejectedException(result.message!, fix: result.fix);
      case CredentialStatus.verified:
        return result;
      case CredentialStatus.unverified:
      case CredentialStatus.unreachable:
        throw CredentialUnreachableException(
          result.message ?? 'The credential could not be checked.',
          fix: result.fix,
        );
    }
  }

  /// What `PUT /projects/{id}/credentials` does with a GitHub token: the
  /// engine's token, checked first.
  Future<Credential> _saveGitHub(
    CredentialFlavor flavor,
    SaveCredentialRequest request,
  ) async {
    final material = CredentialMaterial.fromFields(
      CredentialKind.github,
      request.material,
    );
    _learn(material);
    final result = await _accept(material);
    await material.write(_secrets, githubTokenSecretKey);
    return Credential(
      id: 'github',
      name: CredentialKind.github.label,
      projectId: flavor.projectId,
      app: flavor.appPath,
      flavor: flavor.name,
      kind: CredentialKind.github,
      status: CredentialStatus.verified,
      account: result.account,
      verifiedAt: _clock.now(),
      checkedAt: _clock.now(),
    );
  }

  /// Checks [record] and then each of its assignments.
  Future<CredentialRecord> _checkWithAssignments(
    CredentialRecord record,
  ) async {
    final (checked, material) = await _check(record);
    for (final assignment in await _repository.assignments(
      credentialId: record.id,
    )) {
      await _checkAssignment(assignment.withCredential(checked), material);
    }
    return checked;
  }

  /// Checks the credential itself (does it authenticate) and keeps the
  /// result. Returns it with the secret, if that could be read.
  Future<(CredentialRecord, CredentialMaterial?)> _check(
    CredentialRecord record,
  ) async {
    final CredentialMaterial? material;
    try {
      material = await _load(record);
    } on FormatException catch (error) {
      return (
        await _keep(
          record,
          VerificationResult.rejected(
            'The stored secret cannot be used: ${error.message}',
            fix: 'Replace the secret of the credential.',
          ),
        ),
        null,
      );
    }
    if (material == null) {
      return (
        await _keep(
          record,
          const VerificationResult.rejected(
            'The secret of this credential is missing from the secret store.',
            fix: 'Replace the secret of the credential.',
          ),
        ),
        null,
      );
    }
    final verifier = _verifiers[record.kind];
    final result = verifier == null
        ? VerificationResult.unreachable(
            'This engine cannot check ${record.kind.wire} credentials yet.',
          )
        : await verifier.verify(material, const CredentialTarget());
    return (await _keep(record, result), material);
  }

  /// Checks [assignment] (can the credential reach the flavor's app) and
  /// keeps the result. A kind whose check does not look at the flavor, or a
  /// credential that its own check did not accept, takes the credential's
  /// status.
  Future<AssignedCredential> _checkAssignment(
    AssignedCredential assignment,
    CredentialMaterial? material,
  ) async {
    final verifier = _verifiers[assignment.kind];
    final own = assignment.credential.status;
    final mirrored =
        verifier == null ||
        !verifier.checksTarget ||
        material == null ||
        own == CredentialStatus.rejected ||
        own == CredentialStatus.unreachable;
    final result = mirrored
        ? null
        : await verifier.verify(
            material,
            CredentialTarget.of(assignment.flavor),
          );
    final updated = assignment.checked(
      status: result?.status ?? own,
      at: _clock.now(),
      message: result?.message,
      fix: result?.fix,
    );
    await _repository.assign(updated);
    _events.append(
      CredentialVerified(
        credentialId: assignment.id,
        projectId: assignment.flavor.projectId,
        app: assignment.flavor.appPath,
        flavor: assignment.flavor.name,
        kind: assignment.kind,
        status: updated.check.status,
      ),
    );
    if (result != null &&
        assignment.check.status == CredentialStatus.verified &&
        updated.check.status == CredentialStatus.rejected) {
      _events.append(
        CredentialExpired(
          credentialId: assignment.id,
          name: assignment.credential.name,
          projectId: assignment.flavor.projectId,
          app: assignment.flavor.appPath,
          flavor: assignment.flavor.name,
          kind: assignment.kind,
          message: '${result.message} ${result.fix ?? ''}'.trim(),
        ),
      );
    }
    return updated;
  }

  /// Stores what a check of [record] found and announces it.
  Future<CredentialRecord> _keep(
    CredentialRecord record,
    VerificationResult result,
  ) async {
    final updated = record.checked(
      status: result.status,
      at: _clock.now(),
      account: result.account,
      message: result.message,
      fix: result.fix,
    );
    await _repository.save(updated);
    _events.append(
      CredentialVerified(
        credentialId: record.id,
        kind: record.kind,
        status: result.status,
      ),
    );
    if (record.status == CredentialStatus.verified &&
        updated.status == CredentialStatus.rejected) {
      _events.append(
        CredentialExpired(
          credentialId: record.id,
          name: record.name,
          kind: record.kind,
          message: '${updated.check.message} ${updated.check.fix ?? ''}'.trim(),
        ),
      );
    }
    return updated;
  }

  Future<CredentialMaterial?> _load(CredentialRecord record) async {
    final material = await CredentialMaterial.load(
      record.kind,
      record.secretKey,
      record.account,
      _secrets,
    );
    if (material != null) _learn(material);
    return material;
  }

  /// The secret of [record] for the check of an assignment, or `null` if it
  /// is missing or unusable (the credential's own check says so).
  Future<CredentialMaterial?> _loadOrNull(CredentialRecord record) async {
    try {
      return await _load(record);
    } on FormatException {
      return null;
    }
  }

  Future<void> _unassign(AssignedCredential assignment) async {
    await _repository.unassign(assignment.flavor.id, assignment.kind);
    _announceUnassigned(assignment);
  }

  void _announceUnassigned(AssignedCredential assignment) => _events.append(
    CredentialUnassigned(
      credentialId: assignment.id,
      projectId: assignment.flavor.projectId,
      app: assignment.flavor.appPath,
      flavor: assignment.flavor.name,
      kind: assignment.kind,
    ),
  );

  Future<void> _delete(CredentialRecord record, {String? projectId}) async {
    await _repository.delete(record.id);
    if (await _repository.countUsing(record.secretKey) == 0) {
      await CredentialMaterial.erase(record.kind, record.secretKey, _secrets);
    }
    _events.append(
      CredentialRemoved(
        credentialId: record.id,
        projectId: projectId,
        kind: record.kind,
      ),
    );
  }

  Future<NamedCredential> _named(CredentialRecord record) async =>
      record.toApi(await _repository.assignments(credentialId: record.id));

  void _learn(CredentialMaterial material) =>
      material.secretValues.forEach(_masker.add);

  /// A name made of the kind and the flavor, that no credential has:
  /// "App Store Connect API key · acme/shop prod", with a number after it
  /// when that is taken.
  Future<String> _generatedName(
    CredentialKind kind,
    CredentialFlavor flavor,
  ) async {
    // The project exists: the caller required it.
    final fullName =
        flavor.projectName ?? (await _projects.get(flavor.projectId))!.fullName;
    final project = fullName.isEmpty ? flavor.projectId : fullName;
    final app = flavor.appPath == '.' ? '' : ' ${flavor.appPath}';
    final base = _fit('${kind.label} · $project$app ${flavor.name}');
    var name = base;
    for (var n = 2; await _repository.findByName(name) != null; n++) {
      name = '${_fit(base, room: ' $n'.length)} $n';
    }
    return name;
  }

  static String _fit(String name, {int room = 0}) {
    final limit = maxCredentialNameLength - room;
    return name.length <= limit ? name : name.substring(0, limit).trimRight();
  }

  static String _name(String name) {
    try {
      return credentialName(name);
    } on FormatException catch (error) {
      throw CredentialRequestException(error.message);
    }
  }

  Future<void> _requireFreeName(String name, {String? except}) async {
    final clash = await _repository.findByName(name);
    if (clash != null && clash.id != except) {
      throw CredentialConflictException(
        'A credential is called "${clash.name}" already. Names are unique '
        'regardless of case.',
      );
    }
  }

  static void _requireNamedKind(CredentialKind kind) {
    if (!kind.isNamed) {
      throw const CredentialRequestException(
        'The GitHub token is not a named credential: the engine has one, '
        'shared by every project. Set it with PUT /github-token.',
      );
    }
  }

  /// Throws a [CredentialForbiddenException] unless [by] may [what]: only
  /// `app` and `cli` tokens change credentials.
  static void requireOwner(DeviceToken by, String what) {
    if (by.kind != DeviceTokenKind.app && by.kind != DeviceTokenKind.cli) {
      throw CredentialForbiddenException(
        'A ${by.kind.name} token cannot $what: only the app or `xp` do.',
      );
    }
  }

  Future<void> _requireProject(String projectId) async {
    if (await _projects.get(projectId) == null) {
      throw ProjectNotFoundException(projectId);
    }
  }

  Future<CredentialFlavor> _requireFlavor(
    String projectId,
    String app,
    String flavor,
  ) async =>
      await _repository.findFlavor(projectId, app, flavor) ??
      (throw CredentialNotFoundException(
        'Project $projectId has no flavor "$flavor" in the app at "$app".',
      ));

  Future<CredentialRecord> _require(String id) async =>
      await _repository.get(id) ??
      (throw CredentialNotFoundException('There is no credential $id.'));

  Future<List<AssignedCredential>> _requireUsedIn(
    String projectId,
    CredentialRecord record,
  ) async {
    final usages = await _repository.assignments(
      projectId: projectId,
      credentialId: record.id,
    );
    if (usages.isEmpty) {
      throw CredentialNotFoundException(
        'No flavor of project $projectId uses the credential ${record.id}.',
      );
    }
    return usages;
  }

  static String _places(List<AssignedCredential> usages) => usages
      .map(
        (usage) => [
          usage.flavor.projectName ?? usage.flavor.projectId,
          if (usage.flavor.appPath != '.') usage.flavor.appPath,
          usage.flavor.name,
        ].join(' '),
      )
      .join(', ');

  String _newId() {
    final bytes = List.generate(8, (_) => _random.nextInt(256));
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return 'crd_$hex';
  }

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (_) {});
    return result;
  }
}

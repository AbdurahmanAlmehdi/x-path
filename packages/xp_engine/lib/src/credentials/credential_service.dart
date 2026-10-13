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

/// Saves, checks and removes the credentials of the flavors of projects.
///
/// A credential is verified before it is stored: the store or tool it is for
/// must accept it, else nothing is written and the owner gets the reason and
/// what to do about it. Once stored it is checked again on request and by the
/// daily health check (`CredentialHealthCheck`), and the result is kept with
/// the reference, so that preflight can fail a job before a build starts
/// (`credentials` guard check).
///
/// Secrets live in the [SecretStore] only (D-07); nothing here or in the
/// events and errors contains one, and every secret value is handed to the
/// masker as soon as the engine knows it.
///
/// Operations run one at a time.
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

  /// The credentials of the project, oldest first; only those of the app at
  /// [app] and the flavor [flavor] if given.
  ///
  /// Throws a [ProjectNotFoundException] if there is no such project and a
  /// [CredentialNotFoundException] if [app] and [flavor] name no flavor.
  Future<List<Credential>> list(
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
        for (final record in await _repository.list(projectId: projectId))
          record.toApi(),
      ];
    }
    final target = await _requireFlavor(projectId, app ?? '.', flavor);
    return [
      for (final record in await _repository.list(flavorId: target.id))
        record.toApi(),
    ];
  }

  /// Verifies the credential of [request] and, if it is accepted, stores its
  /// secret and its reference, replacing the credential of the same flavor
  /// and kind. Returns it, and whether it is new.
  ///
  /// Throws a [ProjectNotFoundException], a [CredentialNotFoundException] for
  /// an unknown flavor, a [CredentialRequestException] for a malformed
  /// request, a [CredentialRejectedException] if the store or tool refused
  /// the credential or it is not usable, a [CredentialUnreachableException]
  /// if it could not be checked, and a [SecretStoreException] if the secrets
  /// cannot be written. Whatever is thrown, nothing new is stored.
  Future<({Credential credential, bool created})> save(
    String projectId,
    SaveCredentialRequest request,
  ) => _serial(() async {
    await _requireProject(projectId);
    final flavor = await _requireFlavor(projectId, request.app, request.flavor);
    final verifier = _verifiers[request.kind];
    if (verifier == null) {
      throw CredentialRejectedException(
        'This engine cannot check ${request.kind.wire} credentials yet.',
      );
    }
    final material = CredentialMaterial.fromFields(
      request.kind,
      request.material,
    );
    _learn(material);

    final result = await verifier.verify(material, CredentialTarget.of(flavor));
    switch (result.status) {
      case CredentialStatus.rejected:
        throw CredentialRejectedException(result.message!, fix: result.fix);
      case CredentialStatus.verified:
        break;
      case CredentialStatus.unverified:
      case CredentialStatus.unreachable:
        throw CredentialUnreachableException(
          result.message ?? 'The credential could not be checked.',
          fix: result.fix,
        );
    }

    final existing = await _repository.find(flavor.id, request.kind);
    final id = existing?.id ?? _newId();
    final secretKey = existing?.secretKey ?? _secretKeyOf(request.kind, id);
    await material.write(_secrets, secretKey);
    final now = _clock.now();
    final record =
        (existing ??
                CredentialRecord(
                  id: id,
                  flavor: flavor,
                  kind: request.kind,
                  secretKey: secretKey,
                ))
            .checked(
              status: CredentialStatus.verified,
              at: now,
              account: result.account ?? material.account,
            );
    try {
      await _repository.save(record);
    } on Object {
      if (existing == null) {
        await CredentialMaterial.erase(request.kind, secretKey, _secrets);
      }
      rethrow;
    }
    _events.append(
      CredentialSaved(
        credentialId: id,
        projectId: projectId,
        kind: request.kind,
        replaced: existing != null,
      ),
    );
    return (credential: record.toApi(), created: existing == null);
  });

  /// Checks the credential [credentialId] of the project again and keeps the
  /// result.
  ///
  /// Throws a [CredentialNotFoundException] and a [SecretStoreException] if
  /// the secrets cannot be read.
  Future<Credential> verify(String projectId, String credentialId) =>
      _serial(() async {
        final record = await _require(projectId, credentialId);
        return (await _check(record)).toApi();
      });

  /// Deletes the credential and its secret (a secret another credential
  /// shares stays).
  ///
  /// Throws a [CredentialNotFoundException] and a [SecretStoreException].
  Future<void> remove(String projectId, String credentialId) => _serial(
    () async {
      final record = await _require(projectId, credentialId);
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
    },
  );

  /// Checks every credential of every project and keeps the results: the
  /// daily health check. Returns them.
  ///
  /// A credential that was accepted before and is refused now is announced
  /// as [CredentialExpired]. A credential whose check throws is left as it
  /// was, and the first such error is rethrown after the others were checked.
  ///
  /// Throws a [SecretsLockedException] at once if the secrets are locked.
  Future<List<Credential>> checkAll() => _serial(() async {
    final checked = <Credential>[];
    Object? failure;
    StackTrace? trace;
    for (final record in await _repository.list()) {
      try {
        checked.add((await _check(record)).toApi());
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

  Future<CredentialRecord> _check(CredentialRecord record) async {
    final CredentialMaterial? material;
    try {
      material = await CredentialMaterial.load(
        record.kind,
        record.secretKey,
        record.account,
        _secrets,
      );
    } on FormatException catch (error) {
      return await _keep(
        record,
        VerificationResult.rejected(
          'The stored secret cannot be used: ${error.message}',
          fix: 'Save the credential again.',
        ),
      );
    }
    if (material == null) {
      return await _keep(
        record,
        const VerificationResult.rejected(
          'The secret of this credential is missing from the secret store.',
          fix: 'Save the credential again.',
        ),
      );
    }
    _learn(material);
    final verifier = _verifiers[record.kind];
    final result = verifier == null
        ? VerificationResult.unreachable(
            'This engine cannot check ${record.kind.wire} credentials yet.',
          )
        : await verifier.verify(material, CredentialTarget.of(record.flavor));
    return await _keep(record, result);
  }

  /// Stores what a check found and announces it.
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
        projectId: record.flavor.projectId,
        kind: record.kind,
        status: updated.status,
      ),
    );
    if (record.status == CredentialStatus.verified &&
        updated.status == CredentialStatus.rejected) {
      _events.append(
        CredentialExpired(
          credentialId: record.id,
          projectId: record.flavor.projectId,
          kind: record.kind,
          message: '${updated.message} ${updated.fix ?? ''}'.trim(),
        ),
      );
    }
    return updated;
  }

  void _learn(CredentialMaterial material) =>
      material.secretValues.forEach(_masker.add);

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

  Future<CredentialRecord> _require(String projectId, String id) async {
    await _requireProject(projectId);
    final record = await _repository.get(id);
    if (record == null || record.flavor.projectId != projectId) {
      throw CredentialNotFoundException(
        'Project $projectId has no credential $id.',
      );
    }
    return record;
  }

  /// The secret key of a new credential. The engine has one GitHub token,
  /// shared by every project (the key `xpd secrets import-gh` writes).
  String _secretKeyOf(CredentialKind kind, String id) =>
      kind == CredentialKind.github ? githubTokenSecretKey : 'credential.$id';

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

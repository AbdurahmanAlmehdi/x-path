import 'dart:convert';

import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/credentials/credential_exceptions.dart';
import 'package:xp_engine/src/credentials/credential_repository.dart';
import 'package:xp_engine/src/credentials/credential_service.dart';
import 'package:xp_engine/src/credentials/flavor_asc_key.dart';
import 'package:xp_engine/src/secrets/secret_store.dart';
import 'package:xp_engine/src/stores/apple/app_store_connect.dart';
import 'package:xp_engine/src/stores/apple/asc_exceptions.dart';
import 'package:xp_engine/src/stores/apple/asc_models.dart';
import 'package:xp_engine/src/stores/apple/distribution_keys.dart';
import 'package:xp_engine/src/tokens/device_token.dart';

/// The team has as many distribution certificates as Apple allows, so no new
/// one was made. [certificates] are the ones it could revoke.
class CertificateLimitException extends CredentialException {
  /// Creates the exception for the team's [certificates].
  new(this.certificates)
    : super(
        'The team has ${certificates.length} distribution certificates, '
        "Apple's limit is ${DistributionCertificates.limit}: "
        '${certificates.map(_describe).join('; ')}.',
        fix:
            'Revoke one in App Store Connect (Certificates, Identifiers & '
            'Profiles) and create again, or save the identity of one of them '
            'with --private-key and --certificate.',
      );

  /// The distribution certificates of the team.
  final List<AscCertificate> certificates;

  static String _describe(AscCertificate certificate) => [
    certificate.name ?? 'a certificate',
    'serial ${certificate.serialNumber}',
    if (certificate.expirationDate case final expires?)
      'expires ${expires.toIso8601String().substring(0, 10)}',
  ].join(', ');
}

/// Creates Apple Distribution certificates for owners without a Mac (ADR
/// 0014, Phase 4b): the engine makes the key and the request, App Store
/// Connect signs it with the flavor's API key, which never leaves the engine
/// (D-09), and the identity is saved and assigned to the flavor as any other
/// credential is.
class DistributionCertificates {
  /// Creates the service.
  new({
    required this._credentials,
    required this._repository,
    required this._secrets,
    required this._connect,
    required this._keys,
  });

  /// How many distribution certificates Apple lets a team have.
  static const limit = 3;

  final CredentialService _credentials;
  final CredentialRepository _repository;
  final SecretStore _secrets;
  final AppStoreConnectFactory _connect;
  final DistributionKeys _keys;
  Future<void> _tail = Future.value();

  /// Creates a distribution certificate with the App Store Connect key of
  /// the flavor [flavor] of the app at [app], saves the identity as [name]
  /// and assigns it to the flavor.
  ///
  /// Throws a [CredentialForbiddenException] for a token that may not, a
  /// [CredentialNotFoundException] for an unknown flavor, a
  /// [CredentialRequestException] when the flavor has no App Store Connect
  /// key, a [CredentialConflictException] when the name is taken, a
  /// [CertificateLimitException] when the team is at Apple's limit, and a
  /// [CredentialRejectedException] or [CredentialUnreachableException] when
  /// App Store Connect refuses or cannot be reached.
  Future<NamedCredential> create(
    String projectId, {
    required String app,
    required String flavor,
    required String name,
    required DeviceToken by,
  }) {
    // One at a time: two would both see room under Apple's limit.
    final next = _tail.then(
      (_) => _create(projectId, app: app, flavor: flavor, name: name, by: by),
    );
    _tail = next.then<void>((_) {}, onError: (_) {});
    return next;
  }

  Future<NamedCredential> _create(
    String projectId, {
    required String app,
    required String flavor,
    required String name,
    required DeviceToken by,
  }) async {
    CredentialService.requireOwner(by, 'create certificates');
    final target =
        await _repository.findFlavor(projectId, app, flavor) ??
        (throw CredentialNotFoundException(
          'The project has no flavor "$flavor" in the app at "$app".',
        ));
    final trimmed = credentialName(name);
    if (await _repository.findByName(trimmed) != null) {
      throw CredentialConflictException(
        'A credential is called "$trimmed" already.',
      );
    }
    final key = await flavorAscKey(_repository, _secrets, target.id);
    if (key == null) {
      throw CredentialRequestException(
        'The flavor $flavor has no App Store Connect API key to create the '
        'certificate with. Assign an asc_key credential to it first.',
      );
    }
    final connect = _connect(key);
    final AscCertificate created;
    final String privateKey;
    try {
      final listed = await connect.distributionCertificates();
      if (listed.length >= limit) throw CertificateLimitException(listed);
      final generated = await _keys.generate(trimmed);
      privateKey = generated.privateKeyPem;
      created = await connect.createDistributionCertificate(generated.csrPem);
    } on AppStoreConnectException catch (error) {
      final refusal = ascRefusal(error, key, 'create a certificate');
      throw refusal.status == CredentialStatus.rejected
          ? CredentialRejectedException(refusal.message!, fix: refusal.fix)
          : CredentialUnreachableException(refusal.message!, fix: refusal.fix);
    }
    final NamedCredential identity;
    try {
      final content = created.content;
      if (content == null || content.isEmpty) {
        throw const FormatException('App Store Connect sent no content.');
      }
      identity = await _credentials.create(
        CreateCredentialRequest(
          name: trimmed,
          kind: CredentialKind.appleDistribution,
          material: {
            'privateKey': privateKey,
            'certificate': base64.encode(content),
          },
        ),
        by: by,
      );
    } on Object catch (error) {
      throw await _unsaved(connect, created, error);
    }
    await _credentials.assign(
      projectId,
      app: app,
      flavor: flavor,
      kind: CredentialKind.appleDistribution,
      request: AssignCredentialRequest(credentialId: identity.id),
      by: by,
    );
    return await _credentials.get(identity.id);
  }

  /// What to say when the certificate [created] could not be saved because
  /// of [error]: its key is gone, so it is revoked, to give the team its
  /// slot back, or the owner is told to revoke it.
  Future<CredentialUnreachableException> _unsaved(
    AppStoreConnect connect,
    AscCertificate created,
    Object error,
  ) async {
    final why = switch (error) {
      CredentialException(:final described) => described,
      FormatException(:final message) => message,
      _ => '$error',
    };
    try {
      await connect.revokeCertificate(created.id);
      return CredentialUnreachableException(
        'The engine could not save the certificate it created '
        '(${created.serialNumber}), so it revoked it: $why',
        fix: 'Try again once that is fixed.',
      );
    } on AppStoreConnectException {
      return CredentialUnreachableException(
        'The engine could not save the certificate it created '
        '(${created.serialNumber}): $why',
        fix:
            'Revoke it in App Store Connect (Certificates, Identifiers & '
            "Profiles): its key is lost, and it holds one of the team's "
            '$limit.',
      );
    }
  }
}

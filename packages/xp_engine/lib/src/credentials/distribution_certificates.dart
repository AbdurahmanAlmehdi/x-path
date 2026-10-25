import 'dart:convert';

import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/credentials/credential_exceptions.dart';
import 'package:xp_engine/src/credentials/credential_material.dart';
import 'package:xp_engine/src/credentials/credential_repository.dart';
import 'package:xp_engine/src/credentials/credential_service.dart';
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
  const new({
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
    final assigned = await _repository.assignment(
      target.id,
      CredentialKind.ascKey,
    );
    final key = assigned == null
        ? null
        : await CredentialMaterial.load(
            CredentialKind.ascKey,
            assigned.credential.secretKey,
            assigned.credential.account,
            _secrets,
          );
    if (key is! AscKeyMaterial) {
      throw CredentialRequestException(
        'The flavor $flavor has no App Store Connect API key to create the '
        'certificate with. Assign an asc_key credential to it first.',
      );
    }
    final connect = _connect(key.key);
    final AscCertificate created;
    final String privateKey;
    try {
      final listed = await connect.distributionCertificates();
      if (listed.length >= limit) throw CertificateLimitException(listed);
      final generated = await _keys.generate(trimmed);
      privateKey = generated.privateKeyPem;
      created = await connect.createDistributionCertificate(generated.csrPem);
    } on AscAuthException catch (error) {
      throw CredentialRejectedException(
        'App Store Connect refused the API key ${key.key.keyId}: '
        '${error.message}',
        fix: 'Replace the asc_key credential of the flavor.',
      );
    } on AscForbiddenException catch (error) {
      throw CredentialRejectedException(
        'The API key ${key.key.keyId} may not create certificates: '
        '${error.message}',
        fix: 'Use a key with the Admin role.',
      );
    } on AppStoreConnectException catch (error) {
      throw CredentialUnreachableException(
        'App Store Connect could not create the certificate: '
        '${error.message}',
        fix: 'Try again later.',
      );
    }
    final content = created.content;
    if (content == null || content.isEmpty) {
      throw CredentialUnreachableException(
        'App Store Connect created the certificate ${created.serialNumber} '
        'but sent no content.',
        fix: 'Revoke it in App Store Connect and create again.',
      );
    }
    final identity = await _credentials.create(
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
}

import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/clock/clock.dart';
import 'package:xp_engine/src/credentials/credential_material.dart';
import 'package:xp_engine/src/credentials/credential_repository.dart';
import 'package:xp_engine/src/credentials/credential_verifier.dart';
import 'package:xp_engine/src/secrets/secret_store.dart';
import 'package:xp_engine/src/stores/apple/app_store_connect.dart';
import 'package:xp_engine/src/stores/apple/asc_exceptions.dart';

/// Checks an Apple Distribution identity: on its own, that its certificate
/// has not expired; for a flavor, that App Store Connect lists the
/// certificate among the team's distribution certificates, asked with the
/// flavor's API key (ADR 0014). A certificate that was revoked, or is of
/// another team, is refused, so no Linux build signs with it.
class AppleDistributionVerifier implements CredentialVerifier {
  /// Creates the verifier. `connect` makes the client for the flavor's key,
  /// which `credentials` and `secrets` give.
  const new({
    required this._credentials,
    required this._secrets,
    required this._connect,
    required this._clock,
  });

  final CredentialRepository _credentials;
  final SecretStore _secrets;
  final AppStoreConnectFactory _connect;
  final Clock _clock;

  @override
  CredentialKind get kind => CredentialKind.appleDistribution;

  @override
  bool get checksTarget => true;

  @override
  Future<VerificationResult> verify(
    CredentialMaterial material,
    CredentialTarget target,
  ) async {
    final certificate = (material as AppleDistributionMaterial).certificate;
    final name = certificate.commonName ?? certificate.serialNumber;
    if (!certificate.notAfter.isAfter(_clock.now())) {
      return VerificationResult.rejected(
        'The certificate $name expired on '
        '${certificate.notAfter.toIso8601String().substring(0, 10)}.',
        fix:
            'Create a new Apple Distribution certificate and save the '
            'identity again.',
      );
    }
    final flavorId = target.flavorId;
    if (flavorId == null) {
      return VerificationResult.verified(account: certificate.commonName);
    }
    final assigned = await _credentials.assignment(
      flavorId,
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
      return const VerificationResult.rejected(
        'The flavor has no App Store Connect API key, so the engine can '
        'neither check the certificate nor make the App Store profile.',
        fix:
            'Assign an asc_key credential to the flavor, then check the '
            'identity again (xp credentials verify).',
      );
    }
    try {
      final listed = await _connect(key.key).distributionCertificates();
      if (!listed.any((each) => certificate.hasSerial(each.serialNumber))) {
        return VerificationResult.rejected(
          'App Store Connect lists no distribution certificate with the '
          'serial number ${certificate.serialNumber} in the team of the API '
          'key ${key.key.keyId}: it was revoked, or is of another team.',
          fix:
              'Save the identity of a certificate the team has, or create a '
              'new one.',
        );
      }
      return VerificationResult.verified(account: certificate.commonName);
    } on AscAuthException catch (error) {
      return VerificationResult.rejected(
        'App Store Connect refused the API key ${key.key.keyId}: '
        '${error.message}',
        fix: 'Replace the asc_key credential of the flavor.',
      );
    } on AscForbiddenException catch (error) {
      return VerificationResult.rejected(
        'The API key ${key.key.keyId} may not read the certificates of the '
        'team: ${error.message}',
        fix:
            'Use a key with the Admin role, or App Manager with access to '
            'certificates, identifiers and profiles.',
      );
    } on AppStoreConnectException catch (error) {
      return VerificationResult.unreachable(
        'App Store Connect could not list the certificates: '
        '${error.message}',
        fix: 'Try again later.',
      );
    }
  }
}

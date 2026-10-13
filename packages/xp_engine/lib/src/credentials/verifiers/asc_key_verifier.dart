import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/credentials/credential_material.dart';
import 'package:xp_engine/src/credentials/credential_verifier.dart';
import 'package:xp_engine/src/stores/apple/app_store_connect.dart';
import 'package:xp_engine/src/stores/apple/asc_exceptions.dart';

/// Checks an App Store Connect API key by reading one app with it: a `401` is
/// a key that expired or was revoked.
class AscKeyVerifier implements CredentialVerifier {
  /// Creates the verifier. `connect` makes the client for a key.
  const new(this._connect);

  final AppStoreConnectFactory _connect;

  @override
  CredentialKind get kind => CredentialKind.ascKey;

  @override
  Future<VerificationResult> verify(
    CredentialMaterial material,
    CredentialTarget target,
  ) async {
    final key = (material as AscKeyMaterial).key;
    try {
      await _connect(key).verifyAccess();
      return VerificationResult.verified(account: key.keyId);
    } on FormatException catch (error) {
      return VerificationResult.rejected(
        'The private key of the ASC key cannot be used: ${error.message}',
        fix:
            'Save the key again with the whole .p8 file (a P-256 key, from '
            '-----BEGIN PRIVATE KEY----- to -----END PRIVATE KEY-----).',
      );
    } on AscAuthException catch (error) {
      return VerificationResult.rejected(
        'App Store Connect refused the API key ${key.keyId}: '
        '${error.message}',
        fix:
            'The key has expired or was revoked, or the key id, issuer id or '
            'key kind is wrong. Create a new key in App Store Connect (Users '
            'and Access, Integrations) and save it again.',
      );
    } on AscForbiddenException catch (error) {
      return VerificationResult.rejected(
        "The API key ${key.keyId} may not read the team's apps: "
        '${error.message}',
        fix:
            'Use a key with the App Manager or Admin role, and accept any '
            'new agreement in App Store Connect.',
      );
    } on AppStoreConnectException catch (error) {
      return VerificationResult.unreachable(
        'App Store Connect could not check the key: ${error.message}',
        fix: 'Try again later.',
      );
    }
  }
}

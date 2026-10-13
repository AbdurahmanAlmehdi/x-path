import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/credentials/credential_material.dart';
import 'package:xp_engine/src/credentials/credential_verifier.dart';
import 'package:xp_engine/src/stores/firebase/firebase_app_distribution.dart';
import 'package:xp_engine/src/stores/firebase/firebase_exceptions.dart';
import 'package:xp_engine/src/stores/play/google_play.dart';
import 'package:xp_engine/src/stores/play/play_exceptions.dart';

/// Checks a Google Play service account: Google must accept its signed
/// assertion, and, for a flavor with an Android application id, the account
/// must be able to read the releases of the app's internal track (the account
/// is invited in the Play Console and the API is enabled).
class PlayServiceAccountVerifier implements CredentialVerifier {
  /// Creates the verifier. `connect` makes the client for an account.
  const new(this._connect);

  final GooglePlayFactory _connect;

  @override
  CredentialKind get kind => CredentialKind.playSa;

  @override
  Future<VerificationResult> verify(
    CredentialMaterial material,
    CredentialTarget target,
  ) async {
    final key = (material as ServiceAccountMaterial).key;
    final play = _connect(key);
    try {
      await play.verifyAccess();
      final packageName = target.androidAppId;
      if (packageName != null) {
        await play.releases(packageName, 'internal');
      }
      return VerificationResult.verified(account: key.clientEmail);
    } on PlayAuthException catch (error) {
      return VerificationResult.rejected(
        'Google refused the service account ${key.clientEmail}: '
        '${error.message}',
        fix: error.fix,
      );
    } on PlayForbiddenException catch (error) {
      return VerificationResult.rejected(
        'The service account ${key.clientEmail} may not read '
        '${target.androidAppId}: ${error.message}',
        fix: error.fix,
      );
    } on PlayNotFoundException catch (error) {
      return VerificationResult.rejected(
        'Google Play does not know ${target.androidAppId} for the service '
        'account ${key.clientEmail}: ${error.message}',
        fix: error.fix,
      );
    } on PlayException catch (error) {
      return VerificationResult.unreachable(
        'Google Play could not check the service account: ${error.message}',
        fix: error.fix,
      );
    }
  }
}

/// Checks a Firebase service account: Google must accept its signed
/// assertion with the `cloud-platform` scope. Which apps the account may
/// upload to is not known here (the app ids belong to the steps), so a
/// missing role shows at the first upload, with a fix.
class FirebaseServiceAccountVerifier implements CredentialVerifier {
  /// Creates the verifier. `connect` makes the client for an account.
  const new(this._connect);

  final FirebaseAppDistributionFactory _connect;

  @override
  CredentialKind get kind => CredentialKind.firebaseSa;

  @override
  Future<VerificationResult> verify(
    CredentialMaterial material,
    CredentialTarget target,
  ) async {
    final key = (material as ServiceAccountMaterial).key;
    try {
      await _connect(key).verifyAccess();
      return VerificationResult.verified(account: key.clientEmail);
    } on FirebaseAuthException catch (error) {
      return VerificationResult.rejected(
        'Google refused the service account ${key.clientEmail}: '
        '${error.message}',
        fix: error.fix,
      );
    } on FirebaseException catch (error) {
      return VerificationResult.unreachable(
        'Google could not check the service account: ${error.message}',
        fix: error.fix,
      );
    }
  }
}

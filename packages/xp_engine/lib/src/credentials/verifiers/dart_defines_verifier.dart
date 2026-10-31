import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/credentials/credential_material.dart';
import 'package:xp_engine/src/credentials/credential_verifier.dart';
import 'package:xp_engine/src/steps/build/dart_defines.dart';

/// Checks that a stored define file is one Flutter can read.
class DartDefinesVerifier implements CredentialVerifier {
  /// Creates the verifier.
  const new();

  @override
  CredentialKind get kind => CredentialKind.dartDefines;

  @override
  bool get checksTarget => false;

  @override
  Future<VerificationResult> verify(
    CredentialMaterial material,
    CredentialTarget target,
  ) async {
    try {
      checkDartDefines((material as DartDefinesMaterial).text);
      return const VerificationResult.verified();
    } on FormatException catch (error) {
      return VerificationResult.rejected(error.message);
    }
  }
}

import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/credentials/credential_material.dart';
import 'package:xp_engine/src/credentials/credential_repository.dart';
import 'package:xp_engine/src/credentials/credential_verifier.dart';
import 'package:xp_engine/src/secrets/secret_store.dart';
import 'package:xp_engine/src/stores/apple/asc_exceptions.dart';
import 'package:xp_engine/src/stores/apple/asc_key.dart';

/// The App Store Connect API key the flavor [flavorId] uses, from
/// [credentials] and [secrets]: what the engine checks Apple Distribution
/// identities, makes App Store profiles and creates certificates with (ADR
/// 0014). `null` if the flavor has none, or its secret is missing.
Future<AscKey?> flavorAscKey(
  CredentialRepository credentials,
  SecretStore secrets,
  String flavorId,
) async {
  final assigned = await credentials.assignment(
    flavorId,
    CredentialKind.ascKey,
  );
  if (assigned == null) return null;
  final material = await CredentialMaterial.load(
    CredentialKind.ascKey,
    assigned.credential.secretKey,
    assigned.credential.account,
    secrets,
  );
  return material is AscKeyMaterial ? material.key : null;
}

/// What App Store Connect refusing [key] while the engine tried to [doing]
/// ("create a certificate") says about the credential: a refused or
/// powerless key is rejected, anything else says nothing about it.
VerificationResult ascRefusal(
  AppStoreConnectException error,
  AscKey key,
  String doing,
) => switch (error) {
  AscAuthException() => VerificationResult.rejected(
    'App Store Connect refused the API key ${key.keyId}: ${error.message}',
    fix: 'Replace the asc_key credential of the flavor.',
  ),
  AscForbiddenException() => VerificationResult.rejected(
    'The API key ${key.keyId} may not $doing: ${error.message}',
    fix:
        'Use a key with the Admin role, or App Manager with access to '
        'certificates, identifiers and profiles.',
  ),
  _ => VerificationResult.unreachable(
    'App Store Connect could not $doing: ${error.message}',
    fix: 'Try again later.',
  ),
};

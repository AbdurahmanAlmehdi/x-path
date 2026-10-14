import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xp_secrets/xp_secrets.dart';

/// The Keychain scope of the CLI's tokens: the service is
/// `ly.abdurahman.xpath.client` (ADR 0005).
const clientKeychainScope = 'client';

/// The secret store for the tokens of `xp`.
///
/// macOS: the login Keychain, under the service `ly.abdurahman.xpath.client`.
/// Linux (and `XP_TEST_FILE_SECRETS=1`, for tests and the end-to-end script,
/// which must never touch a Keychain): `secrets.enc` in [configDir], sealed
/// with a master key as for the engine (`$CREDENTIALS_DIRECTORY`, else a
/// 0600 `master.key` beside it).
SecretStore createClientSecretStore({
  required String configDir,
  required Map<String, String> environment,
  required String operatingSystem,
  ProcessRunner runner = const IoProcessRunner(),
}) {
  final fileOnly = environment[fileSecretsVariable] == '1';
  if (operatingSystem == 'macos' && !fileOnly) {
    return KeychainSecretStore(runner: runner, scope: clientKeychainScope);
  }
  if (operatingSystem == 'macos' || operatingSystem == 'linux') {
    return EncryptedFileSecretStore(
      dataDir: configDir,
      runner: runner,
      credentialsDirectory: environment['CREDENTIALS_DIRECTORY'],
    );
  }
  throw UnsupportedError('xp has no secret store for $operatingSystem.');
}

/// Set to `1` to keep the tokens in a file even on macOS. For tests.
const fileSecretsVariable = 'XP_TEST_FILE_SECRETS';

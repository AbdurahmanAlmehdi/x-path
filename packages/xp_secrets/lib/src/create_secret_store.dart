import 'dart:io';

import 'package:xp_engine/xp_engine.dart';
import 'package:xp_secrets/src/encrypted_file/encrypted_file_secret_store.dart';
import 'package:xp_secrets/src/keychain/keychain_secret_store.dart';

/// The secret store for this machine: the Keychain on macOS, the encrypted
/// file in [dataDir] on Linux.
///
/// [runner] runs `security` and `chmod`. [operatingSystem] and [environment]
/// default to the real ones; they are parameters for tests. Throws an
/// [UnsupportedError] on any other system.
SecretStore createSecretStore({
  required ProcessRunner runner,
  required String dataDir,
  String? operatingSystem,
  Map<String, String>? environment,
}) {
  switch (operatingSystem ?? Platform.operatingSystem) {
    case 'macos':
      return KeychainSecretStore(runner: runner);
    case 'linux':
      return EncryptedFileSecretStore(
        dataDir: dataDir,
        runner: runner,
        credentialsDirectory:
            (environment ?? Platform.environment)['CREDENTIALS_DIRECTORY'],
      );
    case final other:
      throw UnsupportedError('No secret store for $other.');
  }
}

import 'dart:io';

import 'package:xp_engine/xp_engine.dart';
import 'package:xp_secrets/src/encrypted_file/encrypted_file_secret_store.dart';
import 'package:xp_secrets/src/keychain/keychain_master_key.dart';
import 'package:xp_secrets/src/keychain/keychain_secret_store.dart';
import 'package:xp_secrets/src/size_routed_secret_store.dart';

/// The Keychain scope, and so service suffix, of the file key on macOS.
const masterKeyKeychainScope = 'master';

/// The secret store for this machine.
///
/// On macOS small secrets are in the Keychain and large ones, which do not
/// fit a `security -i` command line, in the encrypted file in [dataDir],
/// whose key is in the Keychain (ADR 0008). On Linux everything is in the
/// encrypted file in [dataDir].
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
      return SizeRoutedSecretStore(
        small: KeychainSecretStore(runner: runner),
        large: EncryptedFileSecretStore(
          dataDir: dataDir,
          runner: runner,
          masterKey: KeychainMasterKeySource(
            store: KeychainSecretStore(
              runner: runner,
              scope: masterKeyKeychainScope,
            ),
          ),
        ),
      );
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

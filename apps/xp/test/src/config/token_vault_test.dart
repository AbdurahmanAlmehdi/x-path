import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:xp/src/config/client_secret_store.dart';
import 'package:xp/src/config/token_vault.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xp_secrets/xp_secrets.dart';

class _MemorySecrets implements SecretStore {
  final values = <String, String>{};

  @override
  SecretsStatus get status => SecretsStatus.unlocked;

  @override
  Stream<SecretsStatus> get statusChanges => const Stream.empty();

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<Uint8List?> readBytes(String key) async => null;

  @override
  Future<void> writeBytes(String key, List<int> value) async {}

  @override
  Future<void> delete(String key) async => values.remove(key);
}

void main() {
  group('SecretStoreTokenVault', () {
    test('keeps a token per kind', () async {
      final secrets = _MemorySecrets();
      final vault = SecretStoreTokenVault(secrets);

      await vault.write(DeviceTokenKind.cli, 'c');
      await vault.write(DeviceTokenKind.mcp, 'm');

      expect(await vault.read(DeviceTokenKind.cli), 'c');
      expect(await vault.read(DeviceTokenKind.mcp), 'm');
      expect(secrets.values.keys, unorderedEquals(['token.cli', 'token.mcp']));
    });

    test('reads nothing that was never saved', () async {
      expect(
        await SecretStoreTokenVault(_MemorySecrets()).read(DeviceTokenKind.cli),
        isNull,
      );
    });
  });

  group('createClientSecretStore', () {
    late Directory directory;

    setUp(() => directory = Directory.systemTemp.createTempSync('xp_secrets'));
    tearDown(() => directory.deleteSync(recursive: true));

    test('on macOS is the Keychain under the client service', () {
      final store = createClientSecretStore(
        configDir: directory.path,
        environment: const {},
        operatingSystem: 'macos',
      );

      expect(store, isA<KeychainSecretStore>());
      expect((store as KeychainSecretStore).scope, clientKeychainScope);
    });

    test('on Linux is the encrypted file in the config folder', () async {
      final store = createClientSecretStore(
        configDir: directory.path,
        environment: const {},
        operatingSystem: 'linux',
      );

      expect(store, isA<EncryptedFileSecretStore>());
      await store.write('token.cli', 'secret');
      expect(await store.read('token.cli'), 'secret');
      expect(File('${directory.path}/secrets.enc').existsSync(), isTrue);
      expect(
        String.fromCharCodes(
          File('${directory.path}/secrets.enc').readAsBytesSync(),
        ),
        isNot(contains('secret')),
      );
    });

    test('XP_TEST_FILE_SECRETS keeps the tokens out of the Keychain', () {
      final store = createClientSecretStore(
        configDir: directory.path,
        environment: const {fileSecretsVariable: '1'},
        operatingSystem: 'macos',
      );

      expect(store, isA<EncryptedFileSecretStore>());
    });

    test('on another system is unsupported', () {
      expect(
        () => createClientSecretStore(
          configDir: directory.path,
          environment: const {},
          operatingSystem: 'windows',
        ),
        throwsUnsupportedError,
      );
    });
  });
}

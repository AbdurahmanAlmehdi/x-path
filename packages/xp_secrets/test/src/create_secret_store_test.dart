import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xp_secrets/xp_secrets.dart';

void main() {
  final runner = FakeProcessRunner((_) => const ProcessOutput(exitCode: 0));

  test('uses the Keychain and, for large secrets, a file on macOS', () {
    final store = createSecretStore(
      runner: runner,
      dataDir: '/unused',
      operatingSystem: 'macos',
    );

    expect(store, isA<SizeRoutedSecretStore>());
  });

  test('uses the encrypted file on Linux', () {
    final store = createSecretStore(
      runner: runner,
      dataDir: '/unused',
      operatingSystem: 'linux',
      environment: const {},
    );

    expect(store, isA<EncryptedFileSecretStore>());
  });

  test('hands CREDENTIALS_DIRECTORY to the encrypted file', () async {
    final root = Directory.systemTemp.createTempSync('xp_factory_');
    addTearDown(() => root.deleteSync(recursive: true));
    final store = createSecretStore(
      runner: runner,
      dataDir: p.join(root.path, 'data'),
      operatingSystem: 'linux',
      environment: {'CREDENTIALS_DIRECTORY': p.join(root.path, 'nowhere')},
    );

    await expectLater(
      store.write('k', 'v'),
      throwsA(isA<SecretsLockedException>()),
    );
  });

  test('refuses any other system', () {
    expect(
      () => createSecretStore(
        runner: runner,
        dataDir: '/unused',
        operatingSystem: 'windows',
      ),
      throwsA(
        isA<UnsupportedError>().having(
          (e) => e.message,
          'message',
          'No secret store for windows.',
        ),
      ),
    );
  });

  test('defaults to the system it runs on', () {
    if (!Platform.isMacOS && !Platform.isLinux) return;

    final store = createSecretStore(runner: runner, dataDir: '/unused');

    expect(
      store,
      Platform.isMacOS
          ? isA<SizeRoutedSecretStore>()
          : isA<EncryptedFileSecretStore>(),
    );
  });
}

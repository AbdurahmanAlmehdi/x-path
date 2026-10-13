@Tags(['process'])
library;

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xp_secrets/xp_secrets.dart';

import '../helpers/fake_security.dart';
import '../helpers/real_process.dart';

bool _contains(List<int> haystack, List<int> needle) {
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var matches = true;
    for (var j = 0; j < needle.length && matches; j++) {
      matches = haystack[i + j] == needle[j];
    }
    if (matches) return true;
  }
  return false;
}

/// The store `createSecretStore` makes on macOS, with a fake `security` and a
/// real data directory.
void main() {
  late Directory directory;
  late String dataDir;
  late FakeSecurity security;
  late FakeProcessRunner runner;
  late SecretStore store;

  SecretStore newStore() => createSecretStore(
    runner: runner,
    dataDir: dataDir,
    operatingSystem: 'macos',
  );

  setUp(() {
    directory = Directory.systemTemp.createTempSync('xp_macos_secrets_');
    dataDir = p.join(directory.path, 'data');
    security = FakeSecurity();
    runner = FakeProcessRunner(
      (call) =>
          call.executable == 'chmod' ? runForReal(call) : security.handle(call),
    );
    store = newStore();
  });

  tearDown(() => directory.deleteSync(recursive: true));

  const credentials = 'ly.abdurahman.xpath.credentials';
  const master = 'ly.abdurahman.xpath.master/secrets-file-key';
  File secretsFile() => File(p.join(dataDir, 'secrets.enc'));

  Uint8List randomBytes(int count) {
    final random = Random.secure();
    return Uint8List.fromList(List.generate(count, (_) => random.nextInt(256)));
  }

  test('a 16 KB random binary secret round-trips byte for byte', () async {
    final keystore = randomBytes(16 * 1024);

    await store.writeBytes('android.keystore', keystore);

    expect(await store.readBytes('android.keystore'), keystore);
    expect(await newStore().readBytes('android.keystore'), keystore);
  });

  test(
    'a large secret goes to the file, never over the command line',
    () async {
      final keystore = randomBytes(16 * 1024);

      await store.writeBytes('android.keystore', keystore);

      expect(security.items.keys, [master]);
      expect(security.lines.every((line) => line.length < 4094), isTrue);
      expect(secretsFile().existsSync(), isTrue);
      expect(permissionsOf(secretsFile().path), 384); // 0600
      final onDisk = secretsFile().readAsBytesSync();
      expect(
        _contains(onDisk, keystore.sublist(0, 32)),
        isFalse,
        reason: 'the file is encrypted',
      );
    },
  );

  test('the file key is 32 random bytes made once, in the Keychain', () async {
    await store.writeBytes('big', randomBytes(5000));
    final key = security.items[master];
    await store.writeBytes('bigger', randomBytes(6000));

    expect(key, isNotNull);
    expect(security.items[master], key);
    expect(security.items.keys, [master]);
  });

  test('a small secret stays in the Keychain and makes no file', () async {
    await store.write('github.token', 'ghp_example');

    expect(security.items.keys, ['$credentials/github.token']);
    expect(secretsFile().existsSync(), isFalse);
    expect(await store.read('github.token'), 'ghp_example');
  });

  test('text just under and over the limit goes where it should', () async {
    final under = 'a' * 1536; // 2048 base64 characters
    final over = 'a' * 1537;

    await store.write('under', under);
    await store.write('over', over);

    expect(security.items.keys, contains('$credentials/under'));
    expect(security.items.keys, isNot(contains('$credentials/over')));
    expect(await store.read('under'), under);
    expect(await store.read('over'), over);
  });

  test('a secret that grows moves to the file and back', () async {
    await store.write('k', 'small');

    await store.writeBytes('k', randomBytes(4000));
    expect(security.items.keys, isNot(contains('$credentials/k')));

    await store.write('k', 'small again');
    expect(security.items['$credentials/k'], isNotNull);
    expect(await store.read('k'), 'small again');
    expect(await newStore().read('k'), 'small again');

    final reopened = await EncryptedFileSecretStore(
      dataDir: dataDir,
      runner: runner,
      masterKey: KeychainMasterKeySource(
        store: KeychainSecretStore(runner: runner, scope: 'master'),
      ),
    ).readBytes('k');
    expect(reopened, isNull, reason: 'not left in the file');
  });

  test('delete removes the secret wherever it is', () async {
    await store.write('small', 'x');
    await store.writeBytes('big', randomBytes(4000));

    await store.delete('small');
    await store.delete('big');

    expect(await store.read('small'), isNull);
    expect(await store.readBytes('big'), isNull);
    expect(security.items.keys, [master]);
  });

  group('a locked Keychain', () {
    test('locks the whole store', () async {
      await store.write('small', 'x');
      await store.writeBytes('big', randomBytes(4000));
      final fresh = newStore();
      security.locked = true;

      await expectLater(
        fresh.readBytes('big'),
        throwsA(isA<SecretsLockedException>()),
      );
      expect(fresh.status, SecretsStatus.locked);
      await expectLater(
        fresh.write('small', 'y'),
        throwsA(isA<SecretsLockedException>()),
      );
      await expectLater(
        fresh.writeBytes('other', randomBytes(4000)),
        throwsA(isA<SecretsLockedException>()),
      );
    });

    test('unlocks again, and the secrets are still there', () async {
      final value = randomBytes(4000);
      await store.writeBytes('big', value);
      final fresh = newStore();
      security.locked = true;
      await expectLater(
        fresh.readBytes('big'),
        throwsA(isA<SecretsLockedException>()),
      );

      security.locked = false;

      expect(await fresh.readBytes('big'), value);
      expect(fresh.status, SecretsStatus.unlocked);
    });
  });

  test('a file whose key is gone from the Keychain stays locked', () async {
    await store.writeBytes('big', randomBytes(4000));
    security.items.remove(master);
    final fresh = newStore();

    await expectLater(
      fresh.readBytes('big'),
      throwsA(isA<SecretsLockedException>()),
    );
    await expectLater(
      fresh.writeBytes('other', randomBytes(4000)),
      throwsA(isA<SecretsLockedException>()),
    );
    expect(security.items, isEmpty, reason: 'no new key over a sealed file');
  });
}

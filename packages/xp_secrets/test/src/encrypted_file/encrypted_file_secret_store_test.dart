@Tags(['process'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xp_secrets/xp_secrets.dart';

import '../../helpers/real_process.dart';

const _header = [0x58, 0x50, 0x53, 0x45, 0x43, 1]; // "XPSEC", version 1

/// Seals [plain] the way the store does, so tests can plant odd contents.
Future<List<int>> _seal(
  List<int> key,
  List<int> plain, {
  List<int> header = _header,
}) async {
  final box = await Xchacha20.poly1305Aead().encrypt(
    plain,
    secretKey: SecretKey(key),
    aad: header,
  );
  return [...header, ...box.nonce, ...box.cipherText, ...box.mac.bytes];
}

void main() {
  late Directory directory;
  late String dataDir;
  late String secretsPath;
  late String keyPath;
  late EncryptedFileSecretStore store;

  EncryptedFileSecretStore newStore({String? credentialsDirectory}) =>
      EncryptedFileSecretStore(
        dataDir: dataDir,
        runner: chmodRunner(),
        credentialsDirectory: credentialsDirectory,
      );

  void writeKey(String path, List<int> bytes, {String mode = '600'}) {
    File(path).writeAsBytesSync(bytes);
    Process.runSync('chmod', [mode, path]);
  }

  setUp(() {
    directory = Directory.systemTemp.createTempSync('xp_secrets_');
    dataDir = p.join(directory.path, 'data');
    secretsPath = p.join(dataDir, 'secrets.enc');
    keyPath = p.join(dataDir, 'master.key');
    store = newStore();
  });

  tearDown(() => directory.deleteSync(recursive: true));

  group('round trip', () {
    test('reads back what was written', () async {
      await store.write('asc.key', 'hunter2');

      expect(await store.read('asc.key'), 'hunter2');
    });

    test('keeps several secrets apart', () async {
      await store.write('a', '1');
      await store.write('b', '2');

      expect(await store.read('a'), '1');
      expect(await store.read('b'), '2');
    });

    test('keeps multi-line, quoted and non-ASCII values intact', () async {
      const value =
          '-----BEGIN KEY-----\nabc\r\n"q" \\ é ✓\n-----END KEY-----\n';

      await store.write('k', value);

      expect(await store.read('k'), value);
    });

    test('keeps an empty value', () async {
      await store.write('k', '');

      expect(await store.read('k'), '');
    });

    test('replaces a value', () async {
      await store.write('k', 'first');
      await store.write('k', 'second');

      expect(await store.read('k'), 'second');
    });

    test('survives a restart', () async {
      await store.write('k', 'kept');

      expect(await newStore().read('k'), 'kept');
    });

    test('deletes a value and only that value', () async {
      await store.write('a', '1');
      await store.write('b', '2');

      await store.delete('a');

      expect(await store.read('a'), isNull);
      expect(await store.read('b'), '2');
    });

    test('reads null for an unknown key', () async {
      await store.write('a', '1');

      expect(await store.read('other'), isNull);
    });

    test('keeps every write of concurrent operations', () async {
      await Future.wait([
        for (var i = 0; i < 20; i++) store.write('key$i', 'value$i'),
      ]);

      for (var i = 0; i < 20; i++) {
        expect(await store.read('key$i'), 'value$i');
      }
    });

    test('goes on after a failed operation', () async {
      await expectLater(store.write('', 'v'), throwsArgumentError);

      await store.write('k', 'v');

      expect(await store.read('k'), 'v');
    });
  });

  group('before anything is written', () {
    test('read returns null and creates nothing', () async {
      expect(await store.read('k'), isNull);

      expect(Directory(dataDir).existsSync(), isFalse);
      expect(store.status, SecretsStatus.unlocked);
    });

    test('delete does nothing and creates nothing', () async {
      await store.delete('k');

      expect(Directory(dataDir).existsSync(), isFalse);
    });

    test('deleting an unknown key does not rewrite the file', () async {
      await store.write('a', '1');
      final before = File(secretsPath).readAsBytesSync();

      await store.delete('other');

      expect(File(secretsPath).readAsBytesSync(), before);
    });
  });

  group('on disk', () {
    test(
      'the secrets and the key files are readable by the owner only',
      () async {
        await store.write('k', 'v');

        expect(permissionsOf(secretsPath), 384); // 0600
        expect(permissionsOf(keyPath), 384);
      },
    );

    test('the master key is 32 random bytes', () async {
      await store.write('k', 'v');

      final key = File(keyPath).readAsBytesSync();
      expect(key, hasLength(32));
      expect(key.toSet().length, greaterThan(8));
    });

    test(
      'the file holds a header, a nonce, the ciphertext and a tag',
      () async {
        await store.write('k', 'v');

        final bytes = File(secretsPath).readAsBytesSync();
        expect(bytes.sublist(0, 6), _header);
        // {"k":"v"} is 9 bytes.
        expect(bytes, hasLength(6 + 24 + 9 + 16));
      },
    );

    test('the plaintext is not in the file', () async {
      const secret = 'a-very-recognisable-secret-value';

      await store.write('recognisable-key', secret);

      final text = latin1.decode(File(secretsPath).readAsBytesSync());
      expect(text, isNot(contains(secret)));
      expect(text, isNot(contains('recognisable-key')));
    });

    test('every write uses a fresh nonce', () async {
      final nonces = <String>{};
      for (var i = 0; i < 5; i++) {
        await store.write('k', 'same value every time');
        nonces.add(
          base64.encode(File(secretsPath).readAsBytesSync().sublist(6, 30)),
        );
      }

      expect(nonces, hasLength(5));
    });

    test('leaves no temporary file behind', () async {
      await store.write('a', '1');
      await store.write('b', '2');

      expect(
        Directory(dataDir).listSync().map((e) => p.basename(e.path)).toSet(),
        {'secrets.enc', 'master.key'},
      );
    });
  });

  group('the master key', () {
    test('is created on the first write and then reused', () async {
      await store.write('a', '1');
      final key = File(keyPath).readAsBytesSync();

      await newStore().write('b', '2');

      expect(File(keyPath).readAsBytesSync(), key);
    });

    test('is read from the systemd credential when there is one', () async {
      final credentials = Directory(p.join(directory.path, 'creds'))
        ..createSync();
      final key = List.generate(32, (i) => i);
      File(p.join(credentials.path, 'xpath-master-key')).writeAsBytesSync(key);
      final systemd = newStore(credentialsDirectory: credentials.path);

      await systemd.write('k', 'v');

      expect(File(keyPath).existsSync(), isFalse);
      expect(await systemd.read('k'), 'v');
      final sealed = File(secretsPath).readAsBytesSync();
      final plain = await Xchacha20.poly1305Aead().decrypt(
        SecretBox(
          sealed.sublist(30, sealed.length - 16),
          nonce: sealed.sublist(6, 30),
          mac: Mac(sealed.sublist(sealed.length - 16)),
        ),
        secretKey: SecretKey(key),
        aad: _header,
      );
      expect(utf8.decode(plain), '{"k":"v"}');
    });

    test('ignores an empty CREDENTIALS_DIRECTORY', () async {
      await newStore(credentialsDirectory: '').write('k', 'v');

      expect(File(keyPath).existsSync(), isTrue);
    });

    test('locks the store when the systemd credential is missing', () async {
      final empty = Directory(p.join(directory.path, 'creds'))..createSync();
      final systemd = newStore(credentialsDirectory: empty.path);

      await expectLater(
        systemd.write('k', 'v'),
        throwsA(isA<SecretsLockedException>()),
      );
      expect(systemd.status, SecretsStatus.locked);
      expect(File(secretsPath).existsSync(), isFalse);
    });

    test('locks the store when the credential has the wrong size', () async {
      final credentials = Directory(p.join(directory.path, 'creds'))
        ..createSync();
      File(p.join(credentials.path, 'xpath-master-key'))
          .writeAsBytesSync([1, 2, 3]);

      await expectLater(
        newStore(credentialsDirectory: credentials.path).write('k', 'v'),
        throwsA(
          isA<SecretsLockedException>().having(
            (e) => e.message,
            'message',
            contains('exactly 32 bytes'),
          ),
        ),
      );
    });

    test('is never replaced when the secrets file exists without it', () async {
      await store.write('k', 'v');
      File(keyPath).deleteSync();

      await expectLater(
        newStore().write('other', 'v'),
        throwsA(isA<SecretsLockedException>()),
      );
      await expectLater(
        newStore().read('k'),
        throwsA(isA<SecretsLockedException>()),
      );
      expect(File(keyPath).existsSync(), isFalse);
    });

    test('is refused when other users can read the key file', () async {
      await store.write('k', 'v');
      for (final mode in ['644', '640', '604', '660']) {
        Process.runSync('chmod', [mode, keyPath]);

        await expectLater(
          newStore().read('k'),
          throwsA(
            isA<SecretsLockedException>().having(
              (e) => e.message,
              'message',
              allOf(contains('chmod 600'), contains(keyPath)),
            ),
          ),
          reason: 'mode $mode',
        );
      }
    });

    test('is accepted with a stricter mode', () async {
      await store.write('k', 'v');
      Process.runSync('chmod', ['400', keyPath]);

      expect(await newStore().read('k'), 'v');
    });

    test('is refused when it is not 32 bytes', () async {
      await store.write('k', 'v');
      writeKey(keyPath, List.filled(31, 7));

      await expectLater(
        newStore().read('k'),
        throwsA(isA<SecretsLockedException>()),
      );
    });

    test('is refused when it is a directory', () async {
      await store.write('k', 'v');
      File(keyPath).deleteSync();
      Directory(keyPath).createSync();

      await expectLater(
        newStore().read('k'),
        throwsA(
          isA<SecretsLockedException>().having(
            (e) => e.message,
            'message',
            contains('not a regular file'),
          ),
        ),
      );
    });

    test('is refused when it is a symbolic link', () async {
      await store.write('k', 'v');
      final real = p.join(directory.path, 'real.key');
      File(keyPath).renameSync(real);
      Link(keyPath).createSync(real);

      await expectLater(
        newStore().read('k'),
        throwsA(isA<SecretsLockedException>()),
      );
    });

    test(
      'is refused when it cannot be read',
      () async {
        await store.write('k', 'v');
        Process.runSync('chmod', ['000', keyPath]);
        addTearDown(() => Process.runSync('chmod', ['600', keyPath]));

        await expectLater(
          newStore().read('k'),
          throwsA(
            isA<SecretsLockedException>().having(
              (e) => e.message,
              'message',
              contains('Cannot read the master key'),
            ),
          ),
        );
      },
      skip: (Process.runSync('id', ['-u']).stdout as String).trim() == '0'
          ? 'root can read any file'
          : false,
    );

    test('that does not open the file locks the store', () async {
      await store.write('k', 'v');
      writeKey(keyPath, List.filled(32, 9));
      final wrongKey = newStore();

      await expectLater(
        wrongKey.read('k'),
        throwsA(isA<SecretsLockedException>()),
      );
      expect(wrongKey.status, SecretsStatus.locked);
    });

    test('unlocks the store once the key is back', () async {
      await store.write('k', 'v');
      final key = File(keyPath).readAsBytesSync();
      File(keyPath).deleteSync();
      final reopened = newStore();
      await expectLater(
        reopened.read('k'),
        throwsA(isA<SecretsLockedException>()),
      );

      writeKey(keyPath, key);

      expect(await reopened.read('k'), 'v');
      expect(reopened.status, SecretsStatus.unlocked);
    });

    test('is generated from the given random source', () async {
      final source = MasterKeySource(
        dataDir: dataDir,
        runner: chmodRunner(),
        random: _Counting(),
      );

      final key = await source.load(createIfMissing: true);

      expect(key, List.generate(32, (i) => i));
      expect(await source.load(createIfMissing: false), key);
      expect(File(source.keyFilePath).readAsBytesSync(), key);
    });
  });

  group('a damaged file', () {
    late List<int> key;

    setUp(() async {
      await store.write('k', 'v');
      key = File(keyPath).readAsBytesSync();
    });

    test('with a changed byte locks the store', () async {
      final bytes = File(secretsPath).readAsBytesSync();
      bytes[bytes.length - 20] ^= 1;
      File(secretsPath).writeAsBytesSync(bytes);

      await expectLater(
        newStore().read('k'),
        throwsA(isA<SecretsLockedException>()),
      );
    });

    test('with a changed tag locks the store', () async {
      final bytes = File(secretsPath).readAsBytesSync();
      bytes[bytes.length - 1] ^= 1;
      File(secretsPath).writeAsBytesSync(bytes);

      await expectLater(
        newStore().write('k', 'v2'),
        throwsA(isA<SecretsLockedException>()),
      );
    });

    test('that is truncated is not an XPath file', () async {
      File(secretsPath).writeAsBytesSync([1, 2, 3]);

      await expectLater(
        newStore().read('k'),
        throwsA(
          isA<SecretStoreException>()
              .having((e) => e, 'type', isNot(isA<SecretsLockedException>()))
              .having((e) => e.message, 'message', contains('truncated')),
        ),
      );
    });

    test('with another magic is not an XPath file', () async {
      final bytes = File(secretsPath).readAsBytesSync()..[0] = 0x41;
      File(secretsPath).writeAsBytesSync(bytes);

      await expectLater(
        newStore().read('k'),
        throwsA(
          isA<SecretStoreException>().having(
            (e) => e.message,
            'message',
            contains('not an XPath file'),
          ),
        ),
      );
    });

    test('with another version is refused', () async {
      final bytes = File(secretsPath).readAsBytesSync()..[5] = 2;
      File(secretsPath).writeAsBytesSync(bytes);

      await expectLater(
        newStore().read('k'),
        throwsA(
          isA<SecretStoreException>().having(
            (e) => e.message,
            'message',
            contains('format version 2'),
          ),
        ),
      );
    });

    test('sealed under another header does not open', () async {
      // The header is authenticated: the same bytes under a header that says
      // version 1 do not open if they were sealed under another one.
      final sealed = await _seal(
        key,
        utf8.encode('{"k":"v"}'),
        header: [0x58, 0x50, 0x53, 0x45, 0x43, 9],
      );
      File(secretsPath).writeAsBytesSync([..._header, ...sealed.sublist(6)]);

      await expectLater(
        newStore().read('k'),
        throwsA(isA<SecretsLockedException>()),
      );
    });

    for (final (name, plain) in [
      ('is not JSON', 'not json'),
      ('is not a JSON object', '["a"]'),
      ('has a value that is not text', '{"k": 5}'),
    ]) {
      test('whose content $name is invalid', () async {
        File(secretsPath)
            .writeAsBytesSync(await _seal(key, utf8.encode(plain)));

        await expectLater(
          newStore().read('k'),
          throwsA(
            isA<SecretStoreException>().having(
              (e) => e.message,
              'message',
              'The secrets file is not valid.',
            ),
          ),
        );
      });
    }

    test('whose content is not UTF-8 is invalid', () async {
      File(secretsPath).writeAsBytesSync(await _seal(key, [0xff, 0xfe, 0xfd]));

      await expectLater(
        newStore().read('k'),
        throwsA(isA<SecretStoreException>()),
      );
    });
  });

  group('when the disk or chmod fails', () {
    test('reports a chmod that exits non-zero', () async {
      final failing = EncryptedFileSecretStore(
        dataDir: dataDir,
        runner: FakeProcessRunner(
          (_) => const ProcessOutput(exitCode: 1, stderr: 'denied'),
        ),
      );

      await expectLater(
        failing.write('k', 'v'),
        throwsA(
          isA<SecretStoreException>().having(
            (e) => e.message,
            'message',
            contains('chmod failed'),
          ),
        ),
      );
      expect(
        Directory(dataDir).listSync(),
        isEmpty,
        reason: 'no key, no secrets, no temporary file',
      );
    });

    test('reports a chmod that cannot be started', () async {
      final runner = FakeProcessRunner((_) => const ProcessOutput(exitCode: 0))
        ..startError = const ProcessStartException('chmod', 'not found');
      final failing = EncryptedFileSecretStore(
        dataDir: dataDir,
        runner: runner,
      );

      await expectLater(
        failing.write('k', 'v'),
        throwsA(
          isA<SecretStoreException>().having(
            (e) => e.message,
            'message',
            'Cannot run chmod: not found',
          ),
        ),
      );
    });

    test('reports a data directory that cannot be created', () async {
      final blocker = File(p.join(directory.path, 'blocker'))
        ..writeAsStringSync('a file');
      final failing = EncryptedFileSecretStore(
        dataDir: p.join(blocker.path, 'data'),
        runner: chmodRunner(),
      );

      await expectLater(
        failing.write('k', 'v'),
        throwsA(
          isA<SecretStoreException>().having(
            (e) => e.message,
            'message',
            startsWith('Cannot write '),
          ),
        ),
      );
      expect(failing.status, SecretsStatus.unlocked);
    });
  });
}

/// A "random" source whose n-th byte is n.
class _Counting implements Random {
  var _next = 0;

  @override
  int nextInt(int max) => _next++ % max;

  @override
  bool nextBool() => throw UnimplementedError();

  @override
  double nextDouble() => throw UnimplementedError();
}

import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xp_secrets/xp_secrets.dart';

String _b64(String value) => base64.encode(utf8.encode(value));

ProcessOutput _fail(int exitCode, String stderr) =>
    ProcessOutput(exitCode: exitCode, stderr: stderr);

const _notFound = ProcessOutput(
  exitCode: 44,
  stderr:
      'security: SecKeychainSearchCopyNext: The specified item could not be '
      'found in the keychain.\n'
      'find-generic-password: returned -25300\n',
);

/// The length of the command line of a write, without its value.
Future<int> _commandOverhead(FakeProcessRunner runner) async {
  await KeychainSecretStore(runner: runner).write('k', '');
  return runner.calls.last.stdin.length - 1;
}

void main() {
  late FakeProcessRunner runner;
  late KeychainSecretStore store;
  var reply = const ProcessOutput(exitCode: 0);

  setUp(() {
    reply = const ProcessOutput(exitCode: 0);
    runner = FakeProcessRunner((_) => reply);
    store = KeychainSecretStore(runner: runner);
  });

  FakeProcessCall onlyCall() => runner.calls.single;

  group('write', () {
    test('sends one quoted command line on stdin of security -i', () async {
      await store.write('asc.key', 'hunter2!');

      expect(onlyCall().executable, '/usr/bin/security');
      expect(onlyCall().arguments, ['-i']);
      expect(
        onlyCall().stdin,
        '"add-generic-password" "-U" "-a" "asc.key" '
        '"-s" "dev.xpath.credentials" "-w" "${_b64('hunter2!')}"\n',
      );
    });

    test('never puts the value in the arguments', () async {
      const value = r'S3c "q" \ very-secret';

      await store.write('k', value);

      expect(onlyCall().arguments.join(' '), isNot(contains('very-secret')));
      expect(onlyCall().arguments.join(' '), isNot(contains(_b64(value))));
    });

    test('escapes backslashes and quotes in every argument', () async {
      final custom = KeychainSecretStore(
        runner: runner,
        scope: 'sc"ope',
        keychainPath: r'/tmp/my "kc"\x.keychain-db',
      );

      await custom.write(r'a"b\c', 'value');

      expect(
        onlyCall().stdin,
        r'"add-generic-password" "-U" "-a" "a\"b\\c" '
        r'"-s" "dev.xpath.sc\"ope" "-w" "dmFsdWU=" '
        r'"/tmp/my \"kc\"\\x.keychain-db"'
        '\n',
      );
    });

    test('stores multi-line and non-ASCII values on a single line', () async {
      const value = '-----BEGIN KEY-----\nabc\r\ndef é ✓\n-----END KEY-----\n';

      await store.write('k', value);

      final line = onlyCall().stdin;
      expect(line.indexOf('\n'), line.length - 1, reason: 'one line only');
      expect(line, contains('"${_b64(value)}"'));
    });

    test('stores an empty value', () async {
      await store.write('k', '');

      expect(onlyCall().stdin, endsWith('"-w" ""\n'));
    });

    test('uses the scope as the service name and the given keychain', () async {
      final custom = KeychainSecretStore(
        runner: runner,
        scope: 'github',
        keychainPath: '/tmp/test.keychain-db',
      );

      await custom.write('k', 'v');

      expect(onlyCall().stdin, contains('"-s" "dev.xpath.github"'));
      expect(onlyCall().stdin, endsWith('"/tmp/test.keychain-db"\n'));
    });

    test('runs the given security executable', () async {
      final custom = KeychainSecretStore(
        runner: runner,
        securityExecutable: '/opt/security',
      );

      await custom.write('k', 'v');

      expect(onlyCall().executable, '/opt/security');
    });

    test('refuses a value that does not fit on one command line', () async {
      final overhead = await _commandOverhead(runner);
      final fits = (KeychainSecretStore.maxCommandLength - overhead) ~/ 4 * 3;
      runner.calls.clear();

      await store.write('k', 'x' * fits);
      expect(
        onlyCall().stdin.length,
        lessThanOrEqualTo(KeychainSecretStore.maxCommandLength + 1),
      );
      runner.calls.clear();

      final big = 'x' * (fits + 1);
      await expectLater(
        store.write('k', big),
        throwsA(
          isA<SecretStoreException>().having(
            (e) => e.message,
            'message',
            allOf(contains('too large'), isNot(contains(_b64(big)))),
          ),
        ),
      );
      expect(runner.calls, isEmpty);
    });

    test('counts bytes, not characters, against the limit', () async {
      final key = 'é' * 2040; // 2,040 characters, 4,080 bytes

      await expectLater(
        store.write(key, 'v'),
        throwsA(isA<SecretStoreException>()),
      );
      expect(runner.calls, isEmpty);
    });

    test('rejects a keychain path with a line break', () async {
      final custom = KeychainSecretStore(
        runner: runner,
        keychainPath: '/tmp/a\nb',
      );

      await expectLater(custom.write('k', 'v'), throwsArgumentError);
      expect(runner.calls, isEmpty);
    });

    test('rejects a key with a line break', () async {
      await expectLater(store.write('a\nb', 'v'), throwsArgumentError);
      expect(runner.calls, isEmpty);
    });
  });

  group('read', () {
    test('decodes the value that security prints', () async {
      const value = 'multi\nline é ✓ "q" \\';
      reply = ProcessOutput(exitCode: 0, stdout: '${_b64(value)}\n');

      expect(await store.read('k'), value);
      expect(
        onlyCall().stdin,
        '"find-generic-password" "-a" "k" '
        '"-s" "dev.xpath.credentials" "-w"\n',
      );
    });

    test('reads an empty value', () async {
      reply = const ProcessOutput(exitCode: 0, stdout: '\n');

      expect(await store.read('k'), '');
    });

    test('returns null when the item is not found (-25300)', () async {
      reply = _notFound;

      expect(await store.read('k'), isNull);
    });

    test('returns null when only the message says not found', () async {
      reply = _fail(
        1,
        'The specified item could not be found in the keychain.',
      );

      expect(await store.read('k'), isNull);
    });

    test('rejects an item that was not written by XPath', () async {
      reply = const ProcessOutput(exitCode: 0, stdout: 'not base64!!\n');

      await expectLater(
        store.read('k'),
        throwsA(
          isA<SecretStoreException>().having(
            (e) => e.message,
            'message',
            isNot(contains('not base64!!')),
          ),
        ),
      );
    });
  });

  group('delete', () {
    test('sends delete-generic-password', () async {
      await store.delete('k');

      expect(
        onlyCall().stdin,
        '"delete-generic-password" "-a" "k" "-s" "dev.xpath.credentials"\n',
      );
    });

    test('does nothing when the item is not found', () async {
      reply = _notFound;

      await store.delete('k');

      expect(store.status, SecretsStatus.unlocked);
    });
  });

  group('a locked keychain', () {
    for (final (name, stderr) in [
      (
        'interaction not allowed',
        'security: SecKeychainItemCreateFromContent: '
            'User interaction is not allowed.\n'
            'add-generic-password: returned -25308\n',
      ),
      (
        'interaction not allowed, message only',
        'User interaction is not allowed.',
      ),
      ('authentication failed', 'find-generic-password: returned -25293\n'),
      ('cancelled by the user', 'find-generic-password: returned -128\n'),
      ('no default keychain', 'find-generic-password: returned -25307\n'),
    ]) {
      test('maps $name to SecretsLockedException', () async {
        reply = _fail(1, stderr);

        await expectLater(
          store.write('k', 'v'),
          throwsA(isA<SecretsLockedException>()),
        );
        expect(store.status, SecretsStatus.locked);
      });
    }

    test('applies to reads and deletes too', () async {
      reply = _fail(1, 'find-generic-password: returned -25308\n');

      await expectLater(
        store.read('k'),
        throwsA(isA<SecretsLockedException>()),
      );
      await expectLater(
        store.delete('k'),
        throwsA(isA<SecretsLockedException>()),
      );
    });

    test('is unlocked again after the next success, and says so', () async {
      final changes = <SecretsStatus>[];
      store.statusChanges.listen(changes.add);
      reply = _fail(1, 'returned -25308');
      await expectLater(
        store.write('k', 'v'),
        throwsA(isA<SecretsLockedException>()),
      );

      reply = const ProcessOutput(exitCode: 0);
      await store.write('k', 'v');

      expect(store.status, SecretsStatus.unlocked);
      expect(changes, [SecretsStatus.locked, SecretsStatus.unlocked]);
    });

    test('counts a keychain that never answers as locked', () async {
      final hanging = FakeProcessRunner(
        (_) => Completer<ProcessOutput>().future,
      );
      final impatient = KeychainSecretStore(
        runner: hanging,
        timeout: const Duration(milliseconds: 20),
      );

      await expectLater(
        impatient.read('k'),
        throwsA(isA<SecretsLockedException>()),
      );
      expect(hanging.calls.single.killed, isTrue);
      expect(impatient.status, SecretsStatus.locked);
    });
  });

  group('other failures', () {
    test('say what failed, without repeating security output', () async {
      reply = _fail(
        1,
        'security: unknown command "S3cretValue123"\n'
        'add-generic-password: returned -25299\n',
      );

      await expectLater(
        store.write('k', 'v'),
        throwsA(
          isA<SecretStoreException>()
              .having((e) => e, 'type', isNot(isA<SecretsLockedException>()))
              .having(
                (e) => e.message,
                'message',
                allOf(
                  'security add-generic-password failed with exit code 1 '
                  '(security error -25299).',
                  isNot(contains('S3cretValue123')),
                ),
              ),
        ),
      );
      expect(store.status, SecretsStatus.unlocked);
    });

    test('cope with a failure that has no security error code', () async {
      reply = _fail(1, 'security: unknown command "S3cretValue123"');

      await expectLater(
        store.read('k'),
        throwsA(
          isA<SecretStoreException>().having(
            (e) => e.message,
            'message',
            'security find-generic-password failed with exit code 1.',
          ),
        ),
      );
    });

    test('report a security that cannot be started', () async {
      runner.startError = const ProcessStartException(
        '/usr/bin/security',
        'No such file or directory',
      );

      await expectLater(
        store.read('k'),
        throwsA(
          isA<SecretStoreException>().having(
            (e) => e.message,
            'message',
            'Cannot run security: No such file or directory',
          ),
        ),
      );
    });
  });
}

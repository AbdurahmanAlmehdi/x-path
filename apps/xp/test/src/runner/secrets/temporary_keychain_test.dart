import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xp/src/runner/secrets/temporary_keychain.dart';
import 'package:xp_engine/xp_engine.dart';

const _login = '/Users/me/Library/Keychains/login.keychain-db';
const _system = '/Library/Keychains/System.keychain';

void main() {
  late Directory directory;
  late FakeProcessRunner runner;
  late List<String> commands;
  late List<String> searchList;

  /// The `security -i` commands the fake runner was given on standard input.
  List<String> commandsOf(String name) => [
    for (final command in commands)
      if (command.startsWith('"$name"')) command,
  ];

  setUp(() {
    directory = Directory.systemTemp.createTempSync('xp_keychain_');
    addTearDown(() => directory.deleteSync(recursive: true));
    commands = [];
    searchList = [_login, _system];
    runner = FakeProcessRunner((call) {
      final command = call.stdin.trim();
      commands.add(command);
      if (command.startsWith('"list-keychains" "-d" "user" "-s"')) {
        searchList = RegExp('"([^"]+)"')
            .allMatches(command)
            .map((m) => m.group(1)!)
            .skip(4)
            .toList();
        return const ProcessOutput(exitCode: 0);
      }
      if (command.startsWith('"list-keychains"')) {
        return ProcessOutput(
          exitCode: 0,
          stdout: [for (final path in searchList) '    "$path"'].join('\n'),
        );
      }
      if (command.startsWith('"create-keychain"')) {
        File(RegExp('"([^"]+)"').allMatches(command).last.group(1)!)
            .writeAsStringSync('keychain');
      }
      return const ProcessOutput(exitCode: 0);
    });
  });

  Future<TemporaryKeychain> create({Random? random}) =>
      TemporaryKeychain.create(
        runner: runner,
        directory: p.join(directory.path, 'keychains'),
        name: 'job_1',
        random: random,
      );

  group('create', () {
    test('makes an unlocked keychain that never locks again', () async {
      final keychain = await create();

      expect(
        keychain.path,
        p.join(directory.path, 'keychains', 'job_1.keychain-db'),
      );
      expect(commands, [
        '"create-keychain" "-p" "${keychain.password}" "${keychain.path}"',
        '"set-keychain-settings" "${keychain.path}"',
        '"unlock-keychain" "-p" "${keychain.password}" "${keychain.path}"',
      ]);
      expect(File(keychain.path).existsSync(), isTrue);
    });

    test(
      'asks the unlock of this keychain only, never the login one',
      () async {
        final keychain = await create();

        for (final command in commands) {
          expect(command, isNot(contains('login')));
          expect(command, contains(keychain.path));
        }
      },
    );

    test('has a random password of 64 hex digits', () async {
      final first = await create();
      final second = await create();

      expect(first.password, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(first.password, isNot(second.password));
    });

    test('uses the random source it is given', () async {
      final keychain = await create(random: Random(1));
      final again = await create(random: Random(1));

      expect(keychain.password, again.password);
    });

    test('puts the password in no argument of the process', () async {
      final keychain = await create();

      for (final call in runner.calls) {
        expect(call.executable, '/usr/bin/security');
        expect(call.arguments, ['-i']);
        expect(call.arguments.join(' '), isNot(contains(keychain.password)));
      }
    });

    test('says when security cannot be run, without a password', () async {
      runner.startError = const ProcessStartException('security', 'missing');

      await expectLater(
        create(),
        throwsA(
          isA<SecretStoreException>().having(
            (e) => e.message,
            'message',
            contains('Cannot run security'),
          ),
        ),
      );
    });

    test('says when security fails, without repeating its arguments', () async {
      runner.handler = (call) =>
          const ProcessOutput(exitCode: 1, stderr: 'create-keychain -p SECRET');

      await expectLater(
        create(),
        throwsA(
          isA<SecretStoreException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('create-keychain failed'),
              isNot(contains('SECRET')),
            ),
          ),
        ),
      );
    });

    test('says when security does not answer', () async {
      runner.handler = (call) => Completer<ProcessOutput>().future;

      await expectLater(
        TemporaryKeychain.create(
          runner: runner,
          directory: directory.path,
          name: 'job_1',
          timeout: const Duration(milliseconds: 20),
        ),
        throwsA(
          isA<SecretStoreException>().having(
            (e) => e.message,
            'message',
            contains('did not answer'),
          ),
        ),
      );
    });
  });

  group('the search list', () {
    test('gets the keychain first, and is put back by delete', () async {
      final keychain = await create();

      await keychain.addToSearchList();
      expect(searchList, [keychain.path, _login, _system]);
      await keychain.delete();

      expect(searchList, [_login, _system]);
      expect(commandsOf('delete-keychain'), [
        '"delete-keychain" "${keychain.path}"',
      ]);
      expect(File(keychain.path).existsSync(), isFalse);
    });

    test('is added once', () async {
      final keychain = await create();

      await keychain.addToSearchList();
      await keychain.addToSearchList();

      expect(searchList, [keychain.path, _login, _system]);
      expect(
        commandsOf('list-keychains').where((c) => c.contains('"-s"')),
        hasLength(1),
      );
    });

    test('is left alone when the build does not need the keychain', () async {
      final keychain = await create();

      await keychain.delete();

      expect(commandsOf('list-keychains'), isEmpty);
      expect(searchList, [_login, _system]);
    });

    test('does not mind a keychain that is gone already', () async {
      final keychain = await create();
      File(keychain.path).deleteSync();
      runner.handler = (call) =>
          const ProcessOutput(exitCode: 50, stderr: 'not found');

      await keychain.delete();

      expect(File(keychain.path).existsSync(), isFalse);
    });
  });

  group('removeLeftovers', () {
    test(
      'deletes the keychains a dead runner left and takes them off the list',
      () async {
        final left = p.join(directory.path, 'keychains');
        Directory(left).createSync(recursive: true);
        final a = File(p.join(left, 'job_a.keychain-db'))
          ..writeAsStringSync('a');
        final b = File(p.join(left, 'job_b.keychain-db'))
          ..writeAsStringSync('b');
        File(p.join(left, 'notes.txt')).writeAsStringSync('keep');
        searchList = [a.path, _login, _system, b.path];

        final removed = await TemporaryKeychain.removeLeftovers(
          runner: runner,
          directory: left,
        );

        expect(removed, 2);
        expect(searchList, [_login, _system]);
        expect(a.existsSync() || b.existsSync(), isFalse);
        expect(File(p.join(left, 'notes.txt')).existsSync(), isTrue);
        expect(commandsOf('delete-keychain'), hasLength(2));
      },
    );

    test(
      'leaves the search list alone when the leftovers are not on it',
      () async {
        final left = p.join(directory.path, 'keychains');
        Directory(left).createSync(recursive: true);
        File(p.join(left, 'job_a.keychain-db')).writeAsStringSync('a');

        final removed = await TemporaryKeychain.removeLeftovers(
          runner: runner,
          directory: left,
        );

        expect(removed, 1);
        expect(
          commandsOf('list-keychains').where((c) => c.contains('"-s"')),
          isEmpty,
        );
      },
    );

    test('has nothing to do without a folder or without keychains', () async {
      expect(
        await TemporaryKeychain.removeLeftovers(
          runner: runner,
          directory: p.join(directory.path, 'nothing'),
        ),
        0,
      );
      Directory(p.join(directory.path, 'empty')).createSync();
      expect(
        await TemporaryKeychain.removeLeftovers(
          runner: runner,
          directory: p.join(directory.path, 'empty'),
        ),
        0,
      );
      expect(commands, isEmpty);
    });

    test('goes on when security cannot delete one', () async {
      final left = p.join(directory.path, 'keychains');
      Directory(left).createSync(recursive: true);
      final a = File(p.join(left, 'job_a.keychain-db'))..writeAsStringSync('a');
      runner.handler = (call) => call.stdin.contains('delete-keychain')
          ? const ProcessOutput(exitCode: 50)
          : const ProcessOutput(exitCode: 0);

      final removed = await TemporaryKeychain.removeLeftovers(
        runner: runner,
        directory: left,
      );

      expect(removed, 1);
      expect(a.existsSync(), isFalse, reason: 'the file goes all the same');
    });
  });
}

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';

const _machine = '{"frameworkVersion": "3.47.6", "dartSdkVersion": "3.13.5"}';

/// Makes `bin/flutter` in [directory], as a clone of the Flutter repository
/// would.
void _fakeClone(String directory) {
  File(p.join(directory, 'bin', 'flutter'))
    ..createSync(recursive: true)
    ..writeAsStringSync('#!/bin/sh\n');
}

void main() {
  late Directory work;
  late String root;

  setUp(() {
    work = Directory.systemTemp.createTempSync('xp_installer_');
    root = p.join(work.path, 'toolchains', 'flutter');
    addTearDown(() => work.deleteSync(recursive: true));
  });

  GitFlutterInstaller installer(
    FakeProcessRunner runner, {
    Duration timeout = const Duration(seconds: 5),
  }) => GitFlutterInstaller(
    root: root,
    runner: runner,
    cloneTimeout: timeout,
    precacheTimeout: timeout,
  );

  /// A runner whose `git clone` makes a fake SDK and whose `flutter` prints
  /// [flutter].
  FakeProcessRunner runner({
    ProcessOutput clone = const ProcessOutput(exitCode: 0),
    ProcessOutput flutter = const ProcessOutput(exitCode: 0, stdout: _machine),
    void Function(String into)? onClone,
  }) => FakeProcessRunner((call) {
    if (call.executable == 'git') {
      if (clone.exitCode == 0) {
        final into = call.arguments.last;
        (onClone ?? _fakeClone)(into);
      }
      return clone;
    }
    return flutter;
  });

  List<String> leftovers() =>
      Directory(root)
          .listSync()
          .map((entity) => p.basename(entity.path))
          .where((name) => name != '3.47.6')
          .toList();

  group('pathFor and isInstalled', () {
    test('keep one folder per exact version under the root', () async {
      final cache = installer(runner());

      expect(cache.pathFor('3.47.6'), p.join(root, '3.47.6'));
      expect(await cache.isInstalled('3.47.6'), isFalse);

      _fakeClone(cache.pathFor('3.47.6'));

      expect(await cache.isInstalled('3.47.6'), isTrue);
      expect(await cache.isInstalled('3.47.5'), isFalse);
    });

    test('refuse anything but an exact version', () {
      final cache = installer(runner());

      for (final version in ['stable', '--upload-pack=x', '../x', '']) {
        expect(
          () => cache.pathFor(version),
          throwsA(isA<ArgumentError>()),
          reason: version,
        );
      }
    });
  });

  group('install', () {
    test(
      'clones the tag shallowly, moves it into place and precaches',
      () async {
        final fake = runner();

        await installer(fake).install('3.47.6');

        expect(fake.calls, hasLength(2));
        final [clone, precache] = fake.calls;
        expect(clone.executable, 'git');
        expect(clone.arguments.sublist(0, 6), [
          'clone',
          '--depth',
          '1',
          '--branch',
          '3.47.6',
          '--single-branch',
        ]);
        expect(clone.arguments[6], 'https://github.com/flutter/flutter.git');
        expect(p.dirname(clone.arguments.last), root);
        expect(clone.environment, containsPair('GIT_TERMINAL_PROMPT', '0'));
        expect(precache.executable, p.join(root, '3.47.6', 'bin', 'flutter'));
        expect(precache.arguments, ['--version', '--machine']);
        expect(precache.environment, containsPair('CI', 'true'));
        expect(await installer(fake).isInstalled('3.47.6'), isTrue);
        expect(leftovers(), isEmpty);
      },
    );

    test('uses the repository and git it was given', () async {
      final fake = runner();

      await GitFlutterInstaller(
        root: root,
        runner: fake,
        repositoryUrl: 'https://mirror.example/flutter.git',
        gitExecutable: '/usr/local/bin/git',
      ).install('3.47.6');

      expect(fake.calls.first.executable, '/usr/local/bin/git');
      expect(
        fake.calls.first.arguments,
        contains('https://mirror.example/flutter.git'),
      );
    });

    test('leaves nothing behind when the clone fails', () async {
      final fake = runner(
        clone: const ProcessOutput(
          exitCode: 128,
          stderr:
              'Cloning into x...\n'
              'fatal: Remote branch 3.47.6 not found in upstream origin\n',
        ),
      );

      await expectLater(
        installer(fake).install('3.47.6'),
        throwsA(
          isA<FlutterInstallException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('exit 128'),
              contains('Remote branch 3.47.6 not found'),
            ),
          ),
        ),
      );
      expect(leftovers(), isEmpty);
      expect(await installer(fake).isInstalled('3.47.6'), isFalse);
      expect(fake.calls, hasLength(1));
    });

    test('reports a git that cannot be started', () async {
      final fake = FakeProcessRunner((_) => const ProcessOutput(exitCode: 0))
        ..startError = const ProcessStartException('git', 'not found');

      await expectLater(
        installer(fake).install('3.47.6'),
        throwsA(
          isA<FlutterInstallException>().having(
            (e) => e.message,
            'message',
            'Cannot run git: not found',
          ),
        ),
      );
      expect(leftovers(), isEmpty);
    });

    test('gives up on a clone that takes too long', () async {
      final fake = FakeProcessRunner((_) => Completer<ProcessOutput>().future);

      await expectLater(
        installer(
          fake,
          timeout: const Duration(milliseconds: 20),
        ).install('3.47.6'),
        throwsA(
          isA<FlutterInstallException>().having(
            (e) => e.message,
            'message',
            startsWith('git did not finish'),
          ),
        ),
      );
      expect(fake.calls.single.killed, isTrue);
      expect(leftovers(), isEmpty);
    });

    test('removes the SDK again when the precache fails', () async {
      final fake = runner(
        flutter: const ProcessOutput(exitCode: 1, stderr: 'no dart sdk\n'),
      );

      await expectLater(
        installer(fake).install('3.47.6'),
        throwsA(
          isA<FlutterInstallException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('flutter --version failed'),
              contains('no dart sdk'),
            ),
          ),
        ),
      );
      expect(Directory(root).listSync(), isEmpty);
      expect(await installer(fake).isInstalled('3.47.6'), isFalse);
    });

    test('accepts that another install of the version won', () async {
      final fake = runner(
        onClone: (into) {
          _fakeClone(into);
          _fakeClone(p.join(root, '3.47.6'));
        },
      );

      await installer(fake).install('3.47.6');

      expect(fake.calls.map((c) => c.executable), ['git']);
      expect(await installer(fake).isInstalled('3.47.6'), isTrue);
      expect(leftovers(), isEmpty);
    });

    test('reports a folder that cannot be moved into place', () async {
      Directory(root).createSync(recursive: true);
      File(p.join(root, '3.47.6')).writeAsStringSync('in the way');

      await expectLater(
        installer(runner()).install('3.47.6'),
        throwsA(
          isA<FlutterInstallException>().having(
            (e) => e.message,
            'message',
            startsWith('Cannot move the SDK into the cache'),
          ),
        ),
      );
      expect(leftovers(), isEmpty);
    });
  });
}

@Tags(['process'])
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xp/src/runner/runner_paths.dart';
import 'package:xp/src/runner/secrets/secret_area.dart';

int _mode(String path) => FileStat.statSync(path).mode & 0x1FF;

void main() {
  late Directory directory;
  late String active;
  late String stale;
  late SecretArea area;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('xp_secret_area_');
    addTearDown(() => directory.deleteSync(recursive: true));
    active = p.join(directory.path, 'active');
    stale = p.join(directory.path, 'stale');
    area = SecretArea(SecretLocations(active: active, all: [stale, active]));
  });

  group('wipeAll', () {
    test('makes the active place ready, private to the user', () async {
      expect(await area.wipeAll(), 0);

      expect(Directory(active).existsSync(), isTrue);
      expect(_mode(active), 448, reason: '0700');
    });

    test('deletes what a runner that died left, wherever it was', () async {
      for (final place in [active, stale]) {
        File(p.join(place, 'job_1', 'delivered-abc'))
          ..createSync(recursive: true)
          ..writeAsStringSync('secret');
        File(p.join(place, 'job_2', '0-KEY'))
          ..createSync(recursive: true)
          ..writeAsStringSync('secret');
      }

      final removed = await area.wipeAll();

      expect(removed, 4);
      expect(Directory(active).listSync(), isEmpty);
      expect(Directory(stale).existsSync(), isFalse);
    });

    test('fails when the folder cannot be made private', () async {
      final failing = SecretArea(
        SecretLocations(active: active, all: [active]),
        runProcess: (executable, arguments) async =>
            ProcessResult(0, 1, '', 'no way'),
      );

      await expectLater(failing.wipeAll(), throwsA(isA<FileSystemException>()));
    });
  });

  group('the delivered secrets of a job', () {
    setUp(() => area.wipeAll());

    test('are kept in a private file of the job folder', () async {
      await area.keep('job_1', 'credential.crd_1', [0xfe, 0x00, 0xff]);

      final folder = Directory(p.join(active, 'job_1'));
      final file = folder.listSync().single as File;
      expect(p.basename(file.path), startsWith('delivered-'));
      expect(file.readAsBytesSync(), [0xfe, 0x00, 0xff]);
      expect(_mode(file.path), 384, reason: '0600');
      expect(_mode(folder.path), 448, reason: '0700');
      expect(file.path, isNot(contains('crd_1')), reason: 'no key in a name');
    });

    test('are found again by key, only for their job', () async {
      await area.keep('job_1', 'k', [1, 2]);
      await area.keep('job_1', 'other', [3]);

      expect(await area.recall('job_1', 'k'), [1, 2]);
      expect(await area.recall('job_1', 'other'), [3]);
      expect(await area.recall('job_1', 'absent'), isNull);
      expect(await area.recall('job_2', 'k'), isNull);
    });

    test('go with the folder of the job', () async {
      await area.keep('job_1', 'k', [1]);
      await area.keep('job_2', 'k', [2]);

      await area.deleteJob('job_1');

      expect(await area.recall('job_1', 'k'), isNull);
      expect(await area.recall('job_2', 'k'), [2]);
    });

    test('share the folder with the secret files of the steps', () async {
      final path = await area.files.write('job_1', '0-KEY', 'secret');

      await area.keep('job_1', 'k', [1]);

      expect(p.dirname(path), p.join(active, 'job_1'));
      await area.deleteJob('job_1');
      expect(File(path).existsSync(), isFalse);
    });
  });

  group('the places', () {
    const paths = RunnerPaths('/data/runner');

    test('are a tmpfs folder on Linux, below /dev/shm', () {
      final locations = SecretLocations.choose(
        operatingSystem: 'linux',
        environment: {'XDG_RUNTIME_DIR': '/run/user/1000'},
        paths: paths,
        exists: (path) => path == '/dev/shm' || path == '/run/user/1000',
      );

      expect(locations.active, startsWith('/dev/shm/xpath-runner-'));
      expect(locations.all, [
        locations.active,
        startsWith('/run/user/1000/xpath-runner-'),
        '/data/runner/secrets',
      ]);
    });

    test('are the runtime directory on a Linux without /dev/shm', () {
      final locations = SecretLocations.choose(
        operatingSystem: 'linux',
        environment: {'XDG_RUNTIME_DIR': '/run/user/1000'},
        paths: paths,
        exists: (path) => path == '/run/user/1000',
      );

      expect(locations.active, startsWith('/run/user/1000/xpath-runner-'));
    });

    test('are the data directory on a Linux with neither', () {
      final locations = SecretLocations.choose(
        operatingSystem: 'linux',
        environment: {'XDG_RUNTIME_DIR': ''},
        paths: paths,
        exists: (_) => false,
      );

      expect(locations.active, '/data/runner/secrets');
      expect(locations.all, [
        startsWith('/dev/shm/xpath-runner-'),
        '/data/runner/secrets',
      ]);
    });

    test('are the data directory on macOS, which has no tmpfs', () {
      final locations = SecretLocations.choose(
        operatingSystem: 'macos',
        environment: {'XDG_RUNTIME_DIR': '/run/user/1000'},
        paths: paths,
        exists: (_) => true,
      );

      expect(locations.active, '/data/runner/secrets');
      expect(locations.all, ['/data/runner/secrets']);
    });

    test('differ for two runners on one machine', () {
      SecretLocations at(String root) => SecretLocations.choose(
        operatingSystem: 'linux',
        environment: {},
        paths: RunnerPaths(root),
        exists: (path) => path == '/dev/shm',
      );

      expect(at('/data/a').active, isNot(at('/data/b').active));
      expect(at('/data/a').active, at('/data/a').active);
    });

    test('look at the real file system when it is not told otherwise', () {
      final locations = SecretLocations.choose(
        operatingSystem: 'linux',
        environment: {},
        paths: RunnerPaths(directory.path),
      );

      expect(
        locations.active,
        Directory('/dev/shm').existsSync()
            ? startsWith('/dev/shm/xpath-runner-')
            : p.join(directory.path, 'secrets'),
      );
    });
  });
}

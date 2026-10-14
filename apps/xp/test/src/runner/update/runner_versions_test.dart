@Tags(['process'])
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xp/src/runner/runner_paths.dart';
import 'package:xp/src/runner/update/runner_versions.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../helpers/bundle_fixtures.dart';

void main() {
  late Directory directory;
  late RunnerPaths paths;
  late RunnerVersions versions;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('xp_versions_');
    addTearDown(() => directory.deleteSync(recursive: true));
    paths = RunnerPaths(p.join(directory.path, 'runner'));
    versions = RunnerVersions(paths);
  });

  Directory installed(String version) {
    final bundle = writeBundle(directory, version: version);
    versions.install(bundle.path, version);
    return Directory(paths.versionDirectory(version));
  }

  test('names only what is fit to be a folder as a version', () {
    for (final good in ['1.2.3', '0.0.1', '1.2.3-beta.1+7', 'v2']) {
      expect(isVersionName(good), isTrue, reason: good);
    }
    for (final bad in [
      '',
      '..',
      '../x',
      'a/b',
      '-1',
      '.hidden',
      'a b',
      'x' * 65,
    ]) {
      expect(isVersionName(bad), isFalse, reason: bad);
    }
  });

  test('installs a bundle as the folder of its version', () {
    final bundle = writeBundle(directory, version: '1.0.0');

    versions.install(bundle.path, '1.0.0');

    expect(bundle.existsSync(), isFalse, reason: 'it was moved');
    expect(versions.has('1.0.0'), isTrue);
    expect(
      File(p.join(paths.versionDirectory('1.0.0'), 'lib', 'libsqlite3.so'))
          .existsSync(),
      isTrue,
    );
    expect(versions.has('2.0.0'), isFalse);
    expect(versions.has('../1.0.0'), isFalse);
  });

  test('replaces the folder of a version that is installed already', () {
    installed('1.0.0');
    final again = writeBundle(
      directory,
      version: '1.0.0',
      versionOutput: 'again',
    );

    versions.install(again.path, '1.0.0');

    expect(
      File(p.join(paths.versionDirectory('1.0.0'), 'bin', 'xp'))
          .readAsStringSync(),
      contains('again'),
    );
  });

  test('replaces a stray file or link where a version goes', () {
    Directory(paths.versions).createSync(recursive: true);
    File(paths.versionDirectory('1.0.0')).writeAsStringSync('stray');
    final bundle = writeBundle(directory, version: '1.0.0');

    versions.install(bundle.path, '1.0.0');

    expect(versions.has('1.0.0'), isTrue);
  });

  group('current', () {
    test('is not a version until it is switched', () {
      expect(versions.currentVersion(), isNull);
    });

    test('switches to a version with a relative link', () {
      installed('1.0.0');
      installed('1.1.0');

      versions.switchTo('1.0.0');
      expect(versions.currentVersion(), '1.0.0');
      expect(Link(paths.currentLink).targetSync(), p.join('versions', '1.0.0'));
      expect(File(paths.currentExecutable).existsSync(), isTrue);

      versions.switchTo('1.1.0');
      expect(versions.currentVersion(), '1.1.0');
      expect(File('${paths.currentLink}.next').existsSync(), isFalse);
      expect(Link('${paths.currentLink}.next').existsSync(), isFalse);
    });

    test('clears a link a crashed switch left beside it', () {
      installed('1.0.0');
      Link('${paths.currentLink}.next').createSync('versions/nothing');

      versions.switchTo('1.0.0');

      expect(versions.currentVersion(), '1.0.0');
    });

    test('is not replaced when it is a real folder', () {
      installed('1.0.0');
      Directory(paths.currentLink).createSync(recursive: true);

      expect(
        () => versions.switchTo('1.0.0'),
        throwsA(isA<FileSystemException>()),
      );
      expect(Directory(paths.currentLink).existsSync(), isTrue);
    });
  });

  group('adopt', () {
    test('copies the bundle that runs, with its modes', () async {
      final running = writeBundle(directory, version: '1.0.0');

      await versions.adopt(
        bundle: running.path,
        version: '1.0.0',
        runner: const IoProcessRunner(),
      );

      final copy = File(p.join(paths.versionDirectory('1.0.0'), 'bin', 'xp'));
      expect(copy.existsSync(), isTrue);
      expect(copy.statSync().mode & 0x49, isNot(0), reason: 'executable');
      expect(versions.has('1.0.0'), isTrue);
      expect(
        Directory('${paths.versionDirectory('1.0.0')}.partial').existsSync(),
        isFalse,
      );
      expect(running.existsSync(), isTrue, reason: 'the original stays');
    });

    test('replaces an earlier copy', () async {
      installed('1.0.0');
      final running = writeBundle(
        directory,
        version: '1.0.0',
        versionOutput: 'new',
      );

      await versions.adopt(
        bundle: running.path,
        version: '1.0.0',
        runner: const IoProcessRunner(),
      );

      expect(
        File(p.join(paths.versionDirectory('1.0.0'), 'bin', 'xp'))
            .readAsStringSync(),
        contains('new'),
      );
    });

    test('leaves nothing behind when the copy fails', () async {
      await expectLater(
        versions.adopt(
          bundle: p.join(directory.path, 'nothing'),
          version: '1.0.0',
          runner: const IoProcessRunner(),
        ),
        throwsA(isA<FileSystemException>()),
      );

      expect(versions.has('1.0.0'), isFalse);
      expect(
        Directory('${paths.versionDirectory('1.0.0')}.partial').existsSync(),
        isFalse,
      );
    });
  });

  group('prune', () {
    test('keeps the versions asked for and deletes the rest', () {
      installed('1.0.0');
      installed('1.1.0');
      installed('1.2.0');
      Directory('${paths.versionDirectory('1.3.0')}.partial').createSync();

      versions.prune({'1.1.0', '1.2.0'});

      expect(versions.has('1.0.0'), isFalse);
      expect(versions.has('1.1.0'), isTrue);
      expect(versions.has('1.2.0'), isTrue);
      expect(
        Directory('${paths.versionDirectory('1.3.0')}.partial').existsSync(),
        isFalse,
      );
    });

    test('is fine when there are no versions', () {
      expect(() => versions.prune({'1.0.0'}), returnsNormally);
    });
  });

  test('a ProcessRunner that is faked cannot copy', () async {
    final failing = FakeProcessRunner(
      (call) => const ProcessOutput(exitCode: 1, stderr: ' no space '),
    );

    await expectLater(
      versions.adopt(bundle: '/x', version: '1.0.0', runner: failing),
      throwsA(
        isA<FileSystemException>().having(
          (error) => error.message,
          'message',
          contains('no space'),
        ),
      ),
    );
  });
}

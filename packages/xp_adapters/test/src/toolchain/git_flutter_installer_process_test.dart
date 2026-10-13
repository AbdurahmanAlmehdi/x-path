@Tags(['process'])
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/git_fixture.dart';

/// Installs and resolves a "Flutter SDK" with real git and real processes,
/// from a local repository whose tag `3.47.6` holds a `bin/flutter` script.
/// Nothing is downloaded.
void main() {
  late GitFixture upstream;
  late Directory work;

  setUp(() {
    upstream = GitFixture.create();
    work = Directory.systemTemp.createTempSync('xp_installer_process_');
    addTearDown(() {
      upstream.dispose();
      work.deleteSync(recursive: true);
    });

    final script = File(p.join(upstream.seed, 'bin', 'flutter'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        '#!/bin/sh\n'
        'echo \'{"frameworkVersion": "3.47.6", "dartSdkVersion": "3.13.5"}\'\n',
      );
    Process.runSync('chmod', ['755', script.path]);
    upstream
      ..git(['add', '--', 'bin/flutter'])
      ..git(['commit', '--quiet', '-m', 'flutter'])
      ..git(['tag', '3.47.6'])
      ..git(['push', '--quiet', 'origin', 'main', '3.47.6']);
  });

  GitFlutterInstaller installer() => GitFlutterInstaller(
    root: p.join(work.path, 'flutter'),
    runner: const IoProcessRunner(),
    repositoryUrl: upstream.originUrl,
  );

  test('clones the tag into the cache and runs its flutter', () async {
    final cache = installer();

    await cache.install('3.47.6');

    expect(await cache.isInstalled('3.47.6'), isTrue);
    expect(
      Directory(p.join(cache.root)).listSync().map((e) => p.basename(e.path)),
      ['3.47.6'],
    );
  });

  test('fails for a version that does not exist, leaving no folder', () async {
    final cache = installer();

    await expectLater(
      cache.install('3.47.7'),
      throwsA(isA<FlutterInstallException>()),
    );

    expect(await cache.isInstalled('3.47.7'), isFalse);
    expect(Directory(cache.root).listSync(), isEmpty);
  });

  test('FlutterResolver downloads on a miss and reuses it on a hit', () async {
    final resolver = FlutterResolver(
      runner: const IoProcessRunner(),
      installer: installer(),
      fvmExecutable: p.join(work.path, 'no-such-fvm'),
    );

    final first = await resolver.resolve('3.47.6');
    final second = await resolver.resolve('3.47.6');

    expect(first.wasInstalled, isTrue);
    expect(first.source, FlutterSource.cache);
    expect(first.version, '3.47.6');
    expect(first.dartVersion, '3.13.5');
    expect(first.path, p.join(work.path, 'flutter', '3.47.6'));
    expect(second.wasInstalled, isFalse);
    expect(second.path, first.path);
  });
}

@TestOn('mac-os || linux')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

/// Runs the shell scripts of [RunnerProbe] for real, in `/bin/sh`, with an
/// environment of the test's own: the decisions they make are only proven by
/// running them.
void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('xp_probe_scripts_');
    addTearDown(() => root.deleteSync(recursive: true));
  });

  Directory dir(String path) =>
      Directory('${root.path}/$path')..createSync(recursive: true);

  /// An executable [name] in [folder] that runs [body].
  void tool(Directory folder, String name, [String body = 'exit 0']) {
    final file = File('${folder.path}/$name')
      ..writeAsStringSync('#!/bin/sh\n$body\n');
    Process.runSync('chmod', ['+x', file.path]);
  }

  ProcessResult run(String script, Map<String, String> environment) =>
      Process.runSync(
        '/bin/sh',
        ['-c', script],
        environment: environment,
        includeParentEnvironment: false,
      );

  group('android_sdk', () {
    test('finds an SDK in ANDROID_HOME, ANDROID_SDK_ROOT or the home '
        'folder', () {
      final home = dir('home');
      final sdk = dir('sdk');
      dir('sdk/platform-tools');
      final root2 = dir('root2');
      dir('root2/cmdline-tools');
      dir('home/Android/Sdk/build-tools');

      expect(
        run(RunnerProbe.androidSdkScript, {
          'HOME': dir('empty').path,
          'ANDROID_HOME': sdk.path,
        }).exitCode,
        0,
      );
      expect(
        run(RunnerProbe.androidSdkScript, {
          'HOME': dir('empty').path,
          'ANDROID_SDK_ROOT': root2.path,
        }).exitCode,
        0,
      );
      expect(
        run(RunnerProbe.androidSdkScript, {'HOME': home.path}).exitCode,
        0,
      );
    });

    test('finds nothing in an empty folder', () {
      expect(
        run(RunnerProbe.androidSdkScript, {
          'HOME': dir('empty').path,
          'ANDROID_HOME': dir('bare').path,
        }).exitCode,
        1,
      );
    });
  });

  group('java', () {
    test('runs the java of JAVA_HOME first', () {
      final jdk = dir('jdk/bin');
      tool(jdk, 'java', 'echo \'openjdk version "17.0.12"\' >&2');

      final result = run(RunnerProbe.javaScript, {
        'HOME': dir('empty').path,
        'PATH': dir('nothing').path,
        'JAVA_HOME': jdk.parent.path,
      });

      expect(result.exitCode, 0);
      expect(result.stderr, contains('openjdk version "17.0.12"'));
    });

    test('falls back to java on the PATH', skip: _androidStudio, () {
      final bin = dir('bin');
      tool(bin, 'java', 'echo \'openjdk version "21.0.4"\' >&2');

      final result = run(RunnerProbe.javaScript, {
        'HOME': dir('empty').path,
        'PATH': bin.path,
      });

      expect(result.stderr, contains('"21.0.4"'));
    });

    test('exits 127 when there is no JDK at all', () {
      final result = run(RunnerProbe.javaScript, {
        'HOME': dir('empty').path,
        'PATH': dir('nothing').path,
      });

      expect(result.exitCode, 127);
    }, skip: _androidStudio);
  });

  group('flutter_tools', () {
    test('names the tools that are missing', () {
      final bin = dir('bin');
      tool(bin, 'curl');

      final result = run(RunnerProbe.flutterToolsScript, {'PATH': bin.path});

      expect(result.exitCode, 1);
      expect((result.stdout as String).trim(), 'unzip xz');
    });

    test('passes when all of them are there', () {
      final bin = dir('bin');
      for (final name in ['curl', 'unzip', 'xz']) {
        tool(bin, name);
      }

      final result = run(RunnerProbe.flutterToolsScript, {'PATH': bin.path});

      expect(result.exitCode, 0);
      expect(result.stdout, isEmpty);
    });
  });
}

/// Why a test of the JDK fallback cannot run here: Android Studio on this
/// machine brings a JDK the script finds first. `false` when it can.
final Object _androidStudio =
    [
      '/Applications/Android Studio.app',
      '/opt/android-studio',
    ].any((path) => Directory(path).existsSync())
    ? 'Android Studio on this machine brings a JDK, found before the PATH'
    : false;

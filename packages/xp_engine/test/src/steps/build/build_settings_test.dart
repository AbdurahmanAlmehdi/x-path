import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../helpers/build_harness.dart';

void main() {
  final version = AppVersion.parse('1.2.3+45');

  BuildSettings settings({
    String? flavor = 'dev',
    String? target = 'lib/main_dev.dart',
    String? dartDefineFile = '.env.dev',
    bool obfuscate = false,
  }) => BuildSettings(
    worktree: buildWorktree,
    version: version,
    flavor: flavor,
    target: target,
    flutterVersion: '3.47.6',
    dartDefineFile: dartDefineFile,
    obfuscate: obfuscate,
    secretEnvironment: const {'KEYSTORE_PASSWORD': 'keystore.pw'},
    secretFiles: const {'KEYSTORE_FILE': 'keystore.file'},
    passThroughEnvironment: const ['NDK_HOME'],
  );

  group('arguments', () {
    test('build a release of the flavor from its entrypoint', () {
      expect(settings().flutterArguments(), [
        '--release',
        '--flavor',
        'dev',
        '--target',
        'lib/main_dev.dart',
        '--build-name=1.2.3',
        '--build-number=45',
        '--dart-define-from-file=.env.dev',
      ]);
    });

    test('leave out what the app does not use', () {
      expect(
        settings(
          flavor: null,
          target: null,
          dartDefineFile: null,
        ).flutterArguments(),
        ['--release', '--build-name=1.2.3', '--build-number=45'],
      );
    });

    test('split the debug info of an obfuscated build', () {
      expect(
        settings(obfuscate: true).flutterArguments(
          debugInfoDirectory: 'build/xpath/debug-info/android',
        ),
        containsAllInOrder([
          '--obfuscate',
          '--split-debug-info=build/xpath/debug-info/android',
        ]),
      );
      expect(
        settings(obfuscate: true).flutterArguments(),
        isNot(contains('--obfuscate')),
      );
      expect(
        settings().flutterArguments(debugInfoDirectory: 'build/x'),
        isNot(contains('--obfuscate')),
      );
    });

    test('never carry a secret', () {
      expect(
        settings().flutterArguments().join(' '),
        isNot(contains('keystore')),
      );
    });
  });

  group('where it builds', () {
    test('is the app inside the worktree', () {
      expect(settings().appDirectory, appDirectory);
    });

    test('is the worktree for an app at the root', () {
      final root = BuildSettings(
        worktree: const ReleaseWorktree(
          path: '/work/job_1',
          mirror: GitMirror(key: '1', path: '/m'),
          sha: buildSha,
        ),
        version: version,
      );

      expect(root.appDirectory, '/work/job_1');
    });

    test('names its files after the flavor and the version', () {
      expect(settings().label, 'dev-1.2.3+45');
      expect(settings(flavor: null).label, 'app-1.2.3+45');
      expect(settings().build, 45);
    });
  });

  group('JSON', () {
    test('round-trips', () {
      expect(BuildSettings.fromJson(settings().toJson()), settings());
    });

    test('keeps the secret key of the define file', () {
      final json = settings(dartDefineFile: null).toJson();

      expect(json.keys, isNot(contains('dartDefineSecret')));
      expect(
        BuildSettings.fromJson({...json, 'dartDefineSecret': 'defines'})
            .dartDefineSecret,
        'defines',
      );
    });

    test('leaves out what is not set', () {
      final json = BuildSettings(
        worktree: buildWorktree,
        version: version,
      ).toJson();

      expect(json.keys, containsAll(['worktree', 'version', 'obfuscate']));
      expect(json.keys, isNot(contains('flavor')));
      expect(json.keys, isNot(contains('target')));
      expect(json.keys, isNot(contains('flutterVersion')));
      expect(json.keys, isNot(contains('dartDefineFile')));
    });

    test('refuses what is not valid', () {
      final json = settings().toJson();
      for (final bad in <Map<String, dynamic>>[
        {...json, 'version': '1.2.3'},
        {...json, 'version': 'next'},
        {...json}..remove('version'),
        {...json}..remove('worktree'),
        {...json, 'flavor': 'dev/../x'},
        {...json, 'flavor': '1dev'},
        {...json, 'target': '../main.dart'},
        {...json, 'target': '/etc/passwd'},
        {...json, 'target': '--help'},
        {...json, 'target': ''},
        {...json, 'dartDefineFile': 'a/../../b'},
        {...json, 'obfuscate': 'yes'},
        {
          ...json,
          'secretEnvironment': {'A': 1},
        },
        {
          ...json,
          'secretFiles': ['A'],
        },
        {...json, 'passThroughEnvironment': 'A'},
      ]) {
        expect(() => BuildSettings.fromJson(bad), throwsFormatException);
      }
    });
  });

  test('requiredRelative accepts a path inside the app only', () {
    expect(
      requiredRelative({'p': 'ios/Export.plist'}, 'p'),
      'ios/Export.plist',
    );
    expect(() => requiredRelative({}, 'p'), throwsFormatException);
    expect(() => requiredRelative({'p': '../x'}, 'p'), throwsFormatException);
  });

  group('the define file of a credential', () {
    final secret = BuildSettings(
      worktree: buildWorktree,
      version: version,
      dartDefineSecret: 'defines',
    );

    test('is written to the secret folder and passed by its path', () async {
      final context = BuildContext()..defines['defines'] = 'A=secret-value\n';

      final path = await secret.writeSecretDefines(context);

      expect(path, '/secrets/job_1/dart-defines');
      expect(context.secretFiles['dart-defines'], 'A=secret-value\n');
      expect(
        secret.flutterArguments(secretDefines: path),
        contains('--dart-define-from-file=$path'),
      );
    });

    test('is nothing for a build without one', () async {
      final none = BuildSettings(worktree: buildWorktree, version: version);
      final context = BuildContext();

      expect(await none.writeSecretDefines(context), isNull);
      expect(context.secretFiles, isEmpty);
      expect(none.defineArgument(null), isNull);
    });
  });
}

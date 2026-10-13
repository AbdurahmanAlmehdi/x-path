import 'dart:convert';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../helpers/build_harness.dart';

const _aab =
    '$appDirectory/build/app/outputs/bundle/prodRelease/app-prod-release.aab';
const _apk = '$appDirectory/build/app/outputs/flutter-apk/app-prod-release.apk';
const _ipa = '$appDirectory/build/ios/ipa/Mataa.ipa';

void main() {
  late BuildHarness harness;
  late FakeShorebirdReleases releases;
  late InMemoryShorebirdReleaseRepository records;
  late BuildContext context;

  ShorebirdReleaseInput input({
    ShorebirdPlatform platform = ShorebirdPlatform.android,
    ArtifactKind artifact = ArtifactKind.aab,
    bool obfuscate = false,
    String? flutterVersion = '3.47.6',
    String? tokenSecret = 'shorebird.token',
  }) => ShorebirdReleaseInput(
    settings: BuildSettings(
      worktree: buildWorktree,
      version: AppVersion.parse('1.2.3+45'),
      flavor: 'prod',
      target: 'lib/main_prod.dart',
      flutterVersion: flutterVersion,
      dartDefineFile: 'env/prod.json',
      obfuscate: obfuscate,
      secretEnvironment: const {'KEYSTORE_PASSWORD': 'keystore.password'},
      passThroughEnvironment: const ['NDK_HOME'],
    ),
    platform: platform,
    shorebirdAppId: 'sb-1234',
    artifact: artifact,
    exportOptionsPlist: platform == ShorebirdPlatform.ios
        ? 'ios/ExportOptions-prod.plist'
        : null,
    tokenSecret: tokenSecret,
  );

  ShorebirdReleaseStep stepFor({bool isMacOS = false}) => ShorebirdReleaseStep(
    toolchain: harness.toolchain,
    files: harness.files,
    recorder: harness.recorder,
    repository: harness.artifacts,
    store: harness.store,
    releases: releases,
    records: records,
    clock: harness.clock,
    isMacOS: isMacOS,
  );

  setUp(() async {
    harness = BuildHarness(isMacOS: true);
    await harness.createJob();
    releases = FakeShorebirdReleases();
    records = InMemoryShorebirdReleaseRepository();
    context = BuildContext(
      onRun: (_) => harness.files.put(_aab, bytes: utf8.encode('aab bytes')),
    );
  });

  group('the step', () {
    test('is shorebird.release and has a side effect', () {
      final step = stepFor();

      expect(step.kind, 'shorebird.release');
      expect(step.sideEffectOf(input()), isTrue);
    });

    test('stores its input as JSON', () {
      final step = stepFor();

      for (final value in [
        input(),
        input(artifact: ArtifactKind.apk, tokenSecret: null),
        input(platform: ShorebirdPlatform.ios),
      ]) {
        expect(step.decodeInput(step.encodeInput(value)), value);
      }
      expect(step.encodeInput(input())['tokenSecret'], 'shorebird.token');
    });

    test('builds an AAB unless told otherwise', () {
      final json = stepFor().encodeInput(input())..remove('artifact');

      expect(stepFor().decodeInput(json).artifact, ArtifactKind.aab);
    });

    test('refuses input that is not valid', () {
      final step = stepFor();
      final android = step.encodeInput(input());
      final ios = step.encodeInput(input(platform: ShorebirdPlatform.ios));
      for (final bad in <Map<String, dynamic>>[
        {...android, 'platform': 'web'},
        {...android}..remove('platform'),
        {...android, 'artifact': 'ipa'},
        {...android}..remove('shorebirdAppId'),
        {...android, 'tokenSecret': 3},
        {...ios}..remove('exportOptionsPlist'),
        {...ios, 'exportOptionsPlist': '../x.plist'},
      ]) {
        expect(() => step.decodeInput(bad), throwsFormatException);
      }
    });

    test('only builds an apk or an aab', () {
      expect(
        () => ShorebirdReleaseInput(
          settings: input().settings,
          platform: ShorebirdPlatform.android,
          shorebirdAppId: 'sb-1234',
          artifact: ArtifactKind.ipa,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('encodes its result', () {
      const result = ShorebirdReleaseResult(
        artifacts: [],
        flutter: '3.47.6',
        dart: '3.13.5',
        debugInfoDirectory: 'build/xpath/debug-info/android',
        alreadyReleased: true,
      );

      expect(stepFor().encodeResult(result), {
        'artifacts': <Object?>[],
        'flutter': '3.47.6',
        'dart': '3.13.5',
        'debugInfoDirectory': 'build/xpath/debug-info/android',
        'alreadyReleased': true,
      });
      final flutter = ['3.47.6'].single;
      expect(
        ShorebirdReleaseResult(artifacts: const [], flutter: flutter),
        isNot(const ShorebirdReleaseResult(artifacts: [])),
      );
      expect(
        ShorebirdReleaseResult(artifacts: const [], flutter: flutter),
        const ShorebirdReleaseResult(artifacts: [], flutter: '3.47.6'),
      );
    });
  });

  group('run', () {
    test(
      'releases Android with the pinned Flutter and stores the AAB',
      () async {
        final outcome = await stepFor().run(input(), context);

        final result =
            (outcome as StepSucceeded<ShorebirdReleaseResult>).result;
        expect(result.flutter, '3.47.6');
        expect(result.dart, '3.13.5');
        expect(result.alreadyReleased, isFalse);
        expect(result.debugInfoDirectory, isNull);
        final artifact = result.artifacts.single;
        expect(artifact.kind, ArtifactKind.aab);
        expect(artifact.name, 'prod-1.2.3+45.aab');
        expect(
          harness.store.files['job_1/prod-1.2.3+45.aab'],
          utf8.encode('aab bytes'),
        );
      },
    );

    test('runs shorebird release in the app, the token by name', () async {
      await stepFor().run(input(), context);

      final command = context.commands.single;
      expect(command.executable, 'shorebird');
      expect(command.arguments, [
        'release',
        'android',
        '--artifact',
        'aab',
        '--flutter-version=3.47.6',
        '--flavor',
        'prod',
        '--target',
        'lib/main_prod.dart',
        '--build-name=1.2.3',
        '--build-number=45',
        '--',
        '--dart-define-from-file=env/prod.json',
      ]);
      expect(command.workingDirectory, appDirectory);
      expect(command.environment, {'CI': 'true'});
      expect(command.secretEnvironment, {
        'KEYSTORE_PASSWORD': 'keystore.password',
        'SHOREBIRD_TOKEN': 'shorebird.token',
      });
      expect(command.arguments.join(' '), isNot(contains('sb_api')));
      expect(command.passThroughEnvironment, contains('ANDROID_HOME'));
      expect(command.passThroughEnvironment, contains('NDK_HOME'));
    });

    test('uses the login of the machine without a token secret', () async {
      await stepFor().run(input(tokenSecret: null), context);

      expect(context.commands.single.secretEnvironment, {
        'KEYSTORE_PASSWORD': 'keystore.password',
      });
    });

    test('records the Flutter version of the release', () async {
      await stepFor().run(input(), context);

      final record = await records.find(
        'sb-1234',
        AppVersion.parse('1.2.3+45'),
        ShorebirdPlatform.android,
      );
      expect(record!.flutterVersion, '3.47.6');
      expect(record.jobId, 'job_1');
      expect(record.recordedAt, harness.clock.now());
      expect((await harness.jobs.tools('job_1'))!.flutter, '3.47.6');
    });

    test('stores the AAB beside an APK release', () async {
      context.onRun = (_) {
        harness.files
          ..put(_apk, bytes: utf8.encode('apk bytes'))
          ..put(_aab, bytes: utf8.encode('aab bytes'));
      };

      final outcome = await stepFor().run(
        input(artifact: ArtifactKind.apk),
        context,
      );

      final result = (outcome as StepSucceeded<ShorebirdReleaseResult>).result;
      expect(result.artifacts.map((artifact) => artifact.name), [
        'prod-1.2.3+45.apk',
        'prod-1.2.3+45.aab',
      ]);
      expect(context.commands.single.arguments[3], 'apk');
    });

    test('still succeeds when an APK release made no AAB', () async {
      context.onRun = (_) => harness.files.put(_apk);

      final outcome = await stepFor().run(
        input(artifact: ArtifactKind.apk),
        context,
      );

      final result = (outcome as StepSucceeded<ShorebirdReleaseResult>).result;
      expect(result.artifacts.single.name, 'prod-1.2.3+45.apk');
    });

    test('succeeds when an APK release left a stale AAB', () async {
      context.onRun = (_) {
        harness.files
          ..put(_apk)
          ..put(
            _aab,
            modified: harness.files.markedAt.subtract(const Duration(days: 1)),
          );
      };

      final outcome = await stepFor().run(
        input(artifact: ArtifactKind.apk),
        context,
      );

      final result = (outcome as StepSucceeded<ShorebirdReleaseResult>).result;
      expect(result.artifacts, hasLength(1));
    });

    test('obfuscates into the debug info folder', () async {
      final outcome = await stepFor().run(input(obfuscate: true), context);

      final arguments = context.commands.single.arguments;
      expect(
        arguments,
        contains('--split-debug-info=build/xpath/debug-info/android'),
      );
      expect(arguments.sublist(arguments.indexOf('--')), [
        '--',
        '--dart-define-from-file=env/prod.json',
        '--obfuscate',
      ]);
      expect(
        (outcome as StepSucceeded<ShorebirdReleaseResult>)
            .result
            .debugInfoDirectory,
        'build/xpath/debug-info/android',
      );
    });

    test('passes nothing after -- when there is nothing to forward', () async {
      final bare = ShorebirdReleaseInput(
        settings: BuildSettings(
          worktree: buildWorktree,
          version: AppVersion.parse('1.2.3+45'),
          flutterVersion: '3.47.6',
        ),
        platform: ShorebirdPlatform.android,
        shorebirdAppId: 'sb-1234',
      );
      context.onRun = (_) => harness.files.put(
        '$appDirectory/build/app/outputs/bundle/release/app-release.aab',
      );

      await stepFor().run(bare, context);

      final arguments = context.commands.single.arguments;
      expect(arguments, isNot(contains('--')));
      expect(arguments, isNot(contains('--flavor')));
      expect(arguments, isNot(contains('--target')));
    });

    test('releases iOS after clearing the exported IPAs', () async {
      harness.files.put(
        '$appDirectory/build/ios/ipa/Old.ipa',
        modified: harness.files.markedAt.subtract(const Duration(days: 1)),
      );
      context.onRun = (_) => harness.files.put(_ipa);

      final outcome = await stepFor(isMacOS: true)
          .run(input(platform: ShorebirdPlatform.ios), context);

      final result = (outcome as StepSucceeded<ShorebirdReleaseResult>).result;
      expect(result.artifacts.single.kind, ArtifactKind.ipa);
      expect(result.artifacts.single.name, 'prod-1.2.3+45.ipa');
      expect(harness.files.deleted, ['$appDirectory/build/ios/ipa/Old.ipa']);
      final command = context.commands.single;
      expect(command.arguments.take(2), ['release', 'ios']);
      expect(command.arguments, isNot(contains('--artifact')));
      expect(
        command.arguments,
        contains('--export-options-plist=ios/ExportOptions-prod.plist'),
      );
      expect(command.passThroughEnvironment, contains('DEVELOPER_DIR'));
    });

    test('refuses iOS on a machine that is not a Mac', () async {
      final outcome = await stepFor().run(
        input(platform: ShorebirdPlatform.ios),
        context,
      );

      expect(
        (outcome as StepFailed).message,
        contains('needs macOS (ios-sign)'),
      );
      expect(context.commands, isEmpty);
    });

    test('fails when the app pins no Flutter version', () async {
      final outcome = await stepFor().run(input(flutterVersion: null), context);

      expect(
        (outcome as StepFailed).message,
        contains('does not pin a Flutter version'),
      );
      expect(context.commands, isEmpty);
    });

    test('fails when Shorebird fails, and records nothing', () async {
      context.exit = const ProcessExit(exitCode: 1);

      final outcome = await stepFor().run(input(), context);

      expect(
        (outcome as StepFailed).message,
        'shorebird release android exited with code 1. The step log has its '
        'output.',
      );
      expect(await harness.artifacts.forJob('job_1'), isEmpty);
      expect(
        await records.find(
          'sb-1234',
          AppVersion.parse('1.2.3+45'),
          ShorebirdPlatform.android,
        ),
        isNull,
      );
    });

    test('fails when cancelled', () async {
      context.exit = const ProcessExit(exitCode: -15, cancelled: true);

      final outcome = await stepFor().run(input(), context);

      expect(
        (outcome as StepFailed).message,
        'The Shorebird release was cancelled.',
      );
    });

    test(
      'refuses a leftover AAB, and says the version is registered',
      () async {
        context.onRun = (_) => harness.files.put(
          _aab,
          modified: harness.files.markedAt.subtract(const Duration(days: 1)),
        );

        final outcome = await stepFor().run(input(), context);

        final message = (outcome as StepFailed).message;
        expect(message, contains('leftover of an earlier build'));
        expect(message, contains('registered 1.2.3+45 already'));
        // The release exists in Shorebird, so patches still find its version.
        expect(
          await records.find(
            'sb-1234',
            AppVersion.parse('1.2.3+45'),
            ShorebirdPlatform.android,
          ),
          isNotNull,
        );
      },
    );

    test('fails when the build left no file', () async {
      context.onRun = null;

      final outcome = await stepFor().run(input(), context);

      expect(
        (outcome as StepFailed).message,
        contains('no .aab was found under $appDirectory/build'),
      );
    });
  });

  group('alreadyDone', () {
    ShorebirdRelease release({
      String version = '1.2.3+45',
      String? flutter = '3.35.4',
      Set<String> platforms = const {'android'},
    }) => ShorebirdRelease(
      version: AppVersion.parse(version),
      flutterVersion: flutter,
      activePlatforms: platforms,
    );

    test('is not known when Shorebird cannot list the releases', () async {
      expect(await stepFor().alreadyDone(input(), context), isNull);
      expect(releases.lookups, ['sb-1234']);
      expect(releases.tokenSecrets, ['shorebird.token']);
    });

    test('is not done for another version or an unfinished platform', () async {
      releases.answer = [
        release(version: '1.2.3+44'),
        release(platforms: const {}),
        release(platforms: const {'ios'}),
      ];

      expect(await stepFor().alreadyDone(input(), context), isNull);
    });

    test('is done when Shorebird has the release', () async {
      await stepFor().run(input(), context);
      releases.answer = [release(flutter: '3.47.6')];

      final done = await stepFor().alreadyDone(input(), context);

      expect(done!.alreadyReleased, isTrue);
      expect(done.flutter, '3.47.6');
      expect(done.artifacts.single.name, 'prod-1.2.3+45.aab');
    });

    test(
      'records the Flutter version of a release it did not record',
      () async {
        releases.answer = [release()];

        final done = await stepFor().alreadyDone(input(), context);

        expect(done!.artifacts, isEmpty);
        final record = await records.find(
          'sb-1234',
          AppVersion.parse('1.2.3+45'),
          ShorebirdPlatform.android,
        );
        expect(record!.flutterVersion, '3.35.4');
      },
    );

    test('keeps the record that is there', () async {
      await stepFor().run(input(), context);
      releases.answer = [release()];

      await stepFor().alreadyDone(input(), context);

      final record = await records.find(
        'sb-1234',
        AppVersion.parse('1.2.3+45'),
        ShorebirdPlatform.android,
      );
      expect(record!.flutterVersion, '3.47.6');
    });

    test('falls back to the job tools when Shorebird has no version', () async {
      await stepFor().run(input(), context);
      releases.answer = [release(flutter: null)];

      final done = await stepFor().alreadyDone(input(), context);

      expect(done!.flutter, '3.47.6');
      expect(done.dart, '3.13.5');
    });

    test('names no Flutter version when nothing is known', () async {
      releases.answer = [release(flutter: null)];

      final done = await stepFor().alreadyDone(input(), context);

      expect(done!.flutter, isNull);
    });

    test('does not count a stored file that changed', () async {
      await stepFor().run(input(), context);
      harness.store.files['job_1/prod-1.2.3+45.aab'] = [9];
      releases.answer = [release()];

      final done = await stepFor().alreadyDone(input(), context);

      expect(done!.artifacts, isEmpty);
    });
  });
}

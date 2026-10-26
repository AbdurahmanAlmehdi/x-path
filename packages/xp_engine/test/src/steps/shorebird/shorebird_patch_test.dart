import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../helpers/build_harness.dart';

const _ipa = '$appDirectory/build/ios/ipa/Mataa.ipa';

void main() {
  late BuildHarness harness;
  late FakeShorebirdReleases releases;
  late InMemoryShorebirdReleaseRepository records;
  late BuildContext context;

  ShorebirdPatchInput input({
    ShorebirdPlatform platform = ShorebirdPlatform.android,
    bool obfuscate = false,
    bool allowNativeDiffs = false,
    int? patchNumber,
  }) => ShorebirdPatchInput(
    settings: BuildSettings(
      worktree: buildWorktree,
      version: AppVersion.parse('1.2.3+45'),
      flavor: 'prod',
      target: 'lib/main_prod.dart',
      // The pin of today. The patch must not use it.
      flutterVersion: '3.47.6',
      dartDefineFile: 'env/prod.json',
      obfuscate: obfuscate,
    ),
    platform: platform,
    shorebirdAppId: 'sb-1234',
    exportOptionsPlist: platform == ShorebirdPlatform.ios
        ? 'ios/ExportOptions-prod.plist'
        : null,
    allowNativeDiffs: allowNativeDiffs,
    tokenSecret: 'shorebird.token',
    patchNumber: patchNumber,
  );

  ShorebirdPatchStep stepFor({bool isMacOS = true}) => ShorebirdPatchStep(
    toolchain: harness.toolchain,
    files: harness.files,
    releases: releases,
    records: records,
    isMacOS: isMacOS,
  );

  Future<void> recordRelease({
    String flutter = '3.35.4',
    ShorebirdPlatform platform = ShorebirdPlatform.android,
  }) => records.save(
    ShorebirdReleaseRecord(
      appId: 'sb-1234',
      version: AppVersion.parse('1.2.3+45'),
      platform: platform,
      flutterVersion: flutter,
      jobId: 'job_0',
      recordedAt: DateTime.utc(2026, 10),
    ),
  );

  setUp(() async {
    harness = BuildHarness(
      isMacOS: true,
      flutterVersions: {'3.47.6', '3.35.4', '3.32.0'},
    );
    await harness.createJob();
    releases = FakeShorebirdReleases();
    records = InMemoryShorebirdReleaseRepository();
    context = BuildContext();
  });

  group('the step', () {
    test('is shorebird.patch and has a side effect', () {
      expect(stepFor().kind, 'shorebird.patch');
      expect(stepFor().sideEffectOf(input()), isTrue);
    });

    test('stores its input as JSON', () {
      final step = stepFor();

      for (final value in [
        input(),
        input(platform: ShorebirdPlatform.ios, allowNativeDiffs: true),
        input(patchNumber: 3),
      ]) {
        expect(step.decodeInput(step.encodeInput(value)), value);
      }
    });

    test('does not allow native diffs unless told', () {
      final json = stepFor().encodeInput(input())..remove('allowNativeDiffs');

      expect(stepFor().decodeInput(json).allowNativeDiffs, isFalse);
    });

    test('refuses input that is not valid', () {
      final step = stepFor();
      final android = step.encodeInput(input());
      final ios = step.encodeInput(input(platform: ShorebirdPlatform.ios));
      for (final bad in <Map<String, dynamic>>[
        {...android, 'platform': 'web'},
        {...android}..remove('shorebirdAppId'),
        {...android, 'allowNativeDiffs': 'yes'},
        {...android, 'patchNumber': '3'},
        {...ios}..remove('exportOptionsPlist'),
      ]) {
        expect(() => step.decodeInput(bad), throwsFormatException);
      }
    });

    test('encodes its result', () {
      const result = ShorebirdPatchResult(
        releaseVersion: '1.2.3+45',
        flutter: '3.35.4',
        dart: '3.9.2',
        fromShorebird: true,
      );

      expect(stepFor().encodeResult(result), {
        'releaseVersion': '1.2.3+45',
        'flutter': '3.35.4',
        'dart': '3.9.2',
        'fromShorebird': true,
      });
      expect(
        result,
        isNot(
          const ShorebirdPatchResult(
            releaseVersion: '1.2.3+45',
            flutter: '3.35.4',
            fromShorebird: true,
          ),
        ),
      );
    });
  });

  group('run', () {
    test('patches with the Flutter version recorded at release', () async {
      await recordRelease();

      final outcome = await stepFor().run(input(), context);

      final result = (outcome as StepSucceeded<ShorebirdPatchResult>).result;
      expect(result.releaseVersion, '1.2.3+45');
      expect(result.flutter, '3.35.4');
      expect(result.fromShorebird, isFalse);
      // The SDK of the release was resolved, not the pin of the app.
      final sdkCalls = harness.runner.calls
          .map((call) => call.executable)
          .where((executable) => executable.endsWith('/bin/flutter'));
      expect(sdkCalls, ['/data/toolchains/flutter/3.35.4/bin/flutter']);
      expect((await harness.jobs.tools('job_1'))!.flutter, '3.35.4');
    });

    test('runs shorebird patch for the exact release', () async {
      await recordRelease();

      await stepFor().run(input(), context);

      final command = context.commands.single;
      expect(command.executable, 'shorebird');
      expect(command.arguments, [
        'patch',
        'android',
        '--release-version=1.2.3+45',
        '--flavor',
        'prod',
        '--target',
        'lib/main_prod.dart',
        '--',
        '--dart-define-from-file=env/prod.json',
      ]);
      expect(
        command.arguments.where(
          (argument) => argument.contains('flutter-version'),
        ),
        isEmpty,
        reason: 'Shorebird picks the Flutter revision of the release itself.',
      );
      expect(command.workingDirectory, appDirectory);
      expect(command.environment, {'CI': 'true'});
      expect(command.secretEnvironment, {'SHOREBIRD_TOKEN': 'shorebird.token'});
    });

    test(
      'takes the version from Shorebird for a release XPath did not make',
      () async {
        releases.answer = [
          ShorebirdRelease(
            version: AppVersion.parse('1.2.3+44'),
            flutterVersion: '3.32.0',
          ),
          ShorebirdRelease(
            version: AppVersion.parse('1.2.3+45'),
            flutterVersion: '3.32.0',
          ),
        ];

        final outcome = await stepFor().run(input(), context);

        final result = (outcome as StepSucceeded<ShorebirdPatchResult>).result;
        expect(result.flutter, '3.32.0');
        expect(result.fromShorebird, isTrue);
        expect(releases.lookups, ['sb-1234']);
        expect(releases.tokenSecrets, ['shorebird.token']);
      },
    );

    test("prefers the record of XPath to Shorebird's data", () async {
      await recordRelease();
      releases.answer = [
        ShorebirdRelease(
          version: AppVersion.parse('1.2.3+45'),
          flutterVersion: '3.32.0',
        ),
      ];

      final outcome = await stepFor().run(input(), context);

      expect(
        (outcome as StepSucceeded<ShorebirdPatchResult>).result.flutter,
        '3.35.4',
      );
      expect(releases.lookups, isEmpty);
    });

    test('uses the record of the platform it patches', () async {
      await recordRelease(platform: ShorebirdPlatform.ios, flutter: '3.32.0');
      await recordRelease();

      final outcome = await stepFor().run(input(), context);

      expect(
        (outcome as StepSucceeded<ShorebirdPatchResult>).result.flutter,
        '3.35.4',
      );
    });

    test('fails with a fix when the version cannot be determined', () async {
      for (final answer in <List<ShorebirdRelease>?>[
        null,
        const [],
        [
          ShorebirdRelease(
            version: AppVersion.parse('1.2.3+45'),
            flutterVersion: null,
          ),
        ],
      ]) {
        releases.answer = answer;

        final outcome = await stepFor().run(input(), context);

        final message = (outcome as StepFailed).message;
        expect(
          message,
          contains('Flutter version of release 1.2.3+45 is not known'),
        );
        expect(
          message,
          contains('Fix: check that 1.2.3+45 exists for sb-1234'),
        );
      }
      expect(context.commands, isEmpty);
    });

    test('fails when the SDK of the release cannot be had', () async {
      await recordRelease(flutter: '3.1.0');
      harness.installer.failure = const FlutterInstallException('no network');

      final outcome = await stepFor().run(input(), context);

      expect((outcome as StepFailed).message, contains('3.1.0'));
      expect(context.commands, isEmpty);
    });

    test('patches iOS and deletes the IPA the patch builds', () async {
      await recordRelease(platform: ShorebirdPlatform.ios);
      harness.files.put(_ipa);

      final outcome = await stepFor().run(
        input(platform: ShorebirdPlatform.ios),
        context,
      );

      expect(outcome, isA<StepSucceeded<ShorebirdPatchResult>>());
      expect(harness.files.deleted, [_ipa]);
      expect(
        context.commands.single.arguments,
        contains('--export-options-plist=ios/ExportOptions-prod.plist'),
      );
    });

    test('refuses iOS on a machine that is not a Mac', () async {
      final outcome = await stepFor(isMacOS: false)
          .run(input(platform: ShorebirdPlatform.ios), context);

      expect((outcome as StepFailed).message, contains('needs macOS'));
    });

    test(
      'passes the flags of an obfuscated patch with native diffs allowed',
      () async {
        await recordRelease();

        await stepFor().run(
          input(obfuscate: true, allowNativeDiffs: true),
          context,
        );

        final arguments = context.commands.single.arguments;
        expect(
          arguments,
          contains('--split-debug-info=build/xpath/debug-info/android'),
        );
        expect(arguments, contains('--allow-native-diffs'));
        expect(arguments.last, '--obfuscate');
      },
    );

    test('fails when Shorebird fails or is cancelled', () async {
      await recordRelease();
      context.exit = const ProcessExit(exitCode: 70);
      final failed = await stepFor().run(input(), context);
      context.exit = const ProcessExit(exitCode: -15, cancelled: true);
      final cancelled = await stepFor().run(input(), context);

      expect(
        (failed as StepFailed).message,
        'shorebird patch android exited with code 70. The step log has its '
        'output.',
      );
      expect(
        (cancelled as StepFailed).message,
        'The Shorebird patch was cancelled.',
      );
    });
  });
}

import 'dart:convert';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../helpers/build_harness.dart';
import '../../../helpers/fake_build_directories.dart';

const _archive = '$appDirectory/build/ios/archive/Runner.xcarchive';
const _app = '$_archive/Products/Applications/Runner.app';
const _ipa = '$appDirectory/build/ios/ipa/Mataa.ipa';

void main() {
  late BuildHarness harness;
  late FakeBuildDirectories directories;
  late BuildContext context;

  StripAndReexportInput input({
    List<String> frameworks = const [
      'AgoraAudioBeautyExtension',
      'AgoraClearVisionExtension',
      'AgoraReplayKitExtension',
    ],
  }) => StripAndReexportInput(
    settings: BuildSettings(
      worktree: buildWorktree,
      version: AppVersion.parse('1.2.3+45'),
      flavor: 'prod',
    ),
    exportOptionsPlist: 'ios/ExportOptions-prod.plist',
    frameworks: frameworks,
  );

  StripAndReexportStep stepFor({bool isMacOS = true}) => StripAndReexportStep(
    directories: directories,
    files: harness.files,
    recorder: harness.recorder,
    isMacOS: isMacOS,
  );

  setUp(() async {
    harness = BuildHarness(isMacOS: true);
    await harness.createJob();
    directories = FakeBuildDirectories();
    directories.folders
      ..[_app] = 1
      ..['$_app/Frameworks/AgoraAudioBeautyExtension.framework'] = 4096
      ..['$_app/Frameworks/AgoraClearVisionExtension.framework'] = 1024
      ..['$_app/Frameworks/Flutter.framework'] = 9999;
    // The IPA build.ios stored, and the one on disk it came from.
    await harness.recorder.record(
      jobId: 'job_1',
      kind: ArtifactKind.ipa,
      name: 'prod-1.2.3+45.ipa',
      content: Stream.value(utf8.encode('unstripped')),
    );
    harness.files.put(
      _ipa,
      modified: harness.files.markedAt.subtract(const Duration(hours: 1)),
    );
    context = BuildContext(
      onRun: (_) => harness.files.put(_ipa, bytes: utf8.encode('stripped')),
    );
  });

  group('the step', () {
    test('is ios.stripAndReexport and has no side effect', () {
      expect(stepFor().kind, 'ios.stripAndReexport');
      expect(stepFor().sideEffectOf(input()), isFalse);
    });

    test('stores its input as JSON', () {
      expect(stepFor().decodeInput(stepFor().encodeInput(input())), input());
    });

    test('refuses input that is not valid', () {
      final json = stepFor().encodeInput(input());
      for (final bad in <Map<String, dynamic>>[
        {...json, 'frameworks': <String>[]},
        {
          ...json,
          'frameworks': ['../Evil'],
        },
        {
          ...json,
          'frameworks': ['.hidden'],
        },
        {
          ...json,
          'frameworks': ['A/B'],
        },
        {...json}..remove('exportOptionsPlist'),
      ]) {
        expect(() => stepFor().decodeInput(bad), throwsFormatException);
      }
    });

    test('encodes its result', () async {
      final outcome = await stepFor().run(input(), context);
      final result = (outcome as StepSucceeded<StripAndReexportResult>).result;

      expect(stepFor().encodeResult(result), {
        'removed': result.removed,
        'freedBytes': result.freedBytes,
        'artifact': result.artifact.toJson(),
      });
      expect(
        result,
        StripAndReexportResult(
          removed: [...result.removed],
          freedBytes: result.freedBytes,
          artifact: result.artifact,
        ),
      );
    });
  });

  group('run', () {
    test('removes the frameworks that are there and exports again', () async {
      final outcome = await stepFor().run(input(), context);

      final result = (outcome as StepSucceeded<StripAndReexportResult>).result;
      expect(result.removed, [
        'AgoraAudioBeautyExtension',
        'AgoraClearVisionExtension',
      ]);
      expect(result.freedBytes, 5120);
      expect(directories.removed, [
        '$_app/Frameworks/AgoraAudioBeautyExtension.framework',
        '$_app/Frameworks/AgoraClearVisionExtension.framework',
      ]);
      expect(
        directories.folders,
        contains('$_app/Frameworks/Flutter.framework'),
      );
    });

    test('clears the old IPA and runs xcodebuild -exportArchive', () async {
      await stepFor().run(input(), context);

      expect(harness.files.deleted, [_ipa]);
      final command = context.commands.single;
      expect(command.executable, 'xcodebuild');
      expect(command.arguments, [
        '-exportArchive',
        '-archivePath',
        _archive,
        '-exportOptionsPlist',
        '$appDirectory/ios/ExportOptions-prod.plist',
        '-exportPath',
        '$appDirectory/build/ios/ipa',
        '-allowProvisioningUpdates',
        '-quiet',
      ]);
      expect(command.workingDirectory, appDirectory);
      expect(command.passThroughEnvironment, ['DEVELOPER_DIR']);
    });

    test('replaces the IPA that build.ios stored', () async {
      final before = (await harness.artifacts.forJob('job_1')).single;

      final outcome = await stepFor().run(input(), context);

      final result = (outcome as StepSucceeded<StripAndReexportResult>).result;
      expect(result.artifact.id, before.id);
      expect(result.artifact.name, 'prod-1.2.3+45.ipa');
      expect(result.artifact.sha256, isNot(before.sha256));
      expect(
        harness.store.files['job_1/prod-1.2.3+45.ipa'],
        utf8.encode('stripped'),
      );
      expect(await harness.artifacts.forJob('job_1'), hasLength(1));
    });

    test('is skipped when the archive has no app', () async {
      directories.folders.clear();

      final outcome = await stepFor().run(input(), context);

      expect((outcome as StepSkipped).reason, startsWith('No .app inside'));
      expect(context.commands, isEmpty);
    });

    test('is skipped when none of the frameworks is there', () async {
      final outcome = await stepFor().run(
        input(frameworks: const ['Missing']),
        context,
      );

      expect(
        (outcome as StepSkipped).reason,
        'None of the frameworks is in the archive.',
      );
      expect(context.commands, isEmpty);
    });

    test('fails on a machine that is not a Mac', () async {
      final outcome = await stepFor(isMacOS: false).run(input(), context);

      expect((outcome as StepFailed).message, contains('needs macOS'));
      expect(directories.removed, isEmpty);
    });

    test('fails and points at the archive when the export fails', () async {
      context.exit = const ProcessExit(exitCode: 70);

      final outcome = await stepFor().run(input(), context);

      expect(
        (outcome as StepFailed).message,
        allOf(
          contains('xcodebuild exited with code 70'),
          contains('The unstripped archive is still at $_archive'),
        ),
      );
    });

    test('fails when cancelled', () async {
      context.exit = const ProcessExit(exitCode: -15, cancelled: true);

      final outcome = await stepFor().run(input(), context);

      expect((outcome as StepFailed).message, 'The export was cancelled.');
    });

    test('fails when the export wrote no IPA or left a stale one', () async {
      context.onRun = (_) => harness.files.files.clear();
      final missing = await stepFor().run(input(), context);
      directories.folders
        ..[_app] = 1
        ..['$_app/Frameworks/AgoraAudioBeautyExtension.framework'] = 1;
      context.onRun = (_) => harness.files.put(
        _ipa,
        modified: harness.files.markedAt.subtract(const Duration(days: 1)),
      );
      final stale = await stepFor().run(
        input(frameworks: const ['AgoraAudioBeautyExtension']),
        context,
      );

      expect((missing as StepFailed).message, contains('exported no .ipa'));
      expect(
        (stale as StepFailed).message,
        contains('is older than this export'),
      );
    });
  });
}

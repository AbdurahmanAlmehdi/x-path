import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../helpers/build_harness.dart';

const _ipa = '$appDirectory/build/ios/ipa/Mataa.ipa';

void main() {
  late BuildHarness harness;
  late BuildIosStep step;
  late BuildContext context;

  BuildIosInput input() => BuildIosInput(
    settings: BuildSettings(
      worktree: buildWorktree,
      version: AppVersion.parse('1.2.3+45'),
      flavor: 'prod',
      target: 'lib/main_prod.dart',
      flutterVersion: '3.47.6',
    ),
    exportOptionsPlist: 'ios/ExportOptions-prod.plist',
  );

  BuildIosStep stepFor({required bool isMacOS}) => BuildIosStep(
    toolchain: harness.toolchain,
    files: harness.files,
    recorder: harness.recorder,
    repository: harness.artifacts,
    store: harness.store,
    isMacOS: isMacOS,
  );

  setUp(() async {
    harness = BuildHarness(isMacOS: true);
    await harness.createJob();
    step = stepFor(isMacOS: true);
    context = BuildContext(onRun: (_) => harness.files.put(_ipa));
  });

  group('the step', () {
    test('is build.ios and has no side effect', () {
      expect(step.kind, 'build.ios');
      expect(step.sideEffectOf(input()), isFalse);
    });

    test('stores its input as JSON', () {
      expect(step.decodeInput(step.encodeInput(input())), input());
      final linux = BuildIosInput(
        settings: input().settings,
        exportOptionsPlist: 'ios/ExportOptions-prod.plist',
        linuxSigning: const {'ASC_PROFILE': 'identity.profile:ly.mataa'},
      );
      expect(step.decodeInput(step.encodeInput(linux)), linux);
      expect(step.encodeInput(input()), isNot(contains('linuxSigning')));
      expect(
        step.encodeInput(input())['exportOptionsPlist'],
        'ios/ExportOptions-prod.plist',
      );
    });

    test('refuses export options that are missing or leave the app', () {
      final json = step.encodeInput(input());
      expect(
        () => step.decodeInput({...json}..remove('exportOptionsPlist')),
        throwsFormatException,
      );
      expect(
        () => step.decodeInput({...json, 'exportOptionsPlist': '../x.plist'}),
        throwsFormatException,
      );
    });
  });

  group('run', () {
    test('builds the IPA with the export options and stores it', () async {
      final outcome = await step.run(input(), context);

      final result = (outcome as StepSucceeded<BuildResult>).result;
      expect(result.artifact.kind, ArtifactKind.ipa);
      expect(result.artifact.name, 'prod-1.2.3+45.ipa');
      expect(context.commands.single.arguments, [
        'build',
        'ipa',
        '--export-options-plist=ios/ExportOptions-prod.plist',
        '--release',
        '--flavor',
        'prod',
        '--target',
        'lib/main_prod.dart',
        '--build-name=1.2.3',
        '--build-number=45',
      ]);
      expect(
        context.commands.single.passThroughEnvironment,
        contains('DEVELOPER_DIR'),
      );
      expect(context.commands.single.workingDirectory, appDirectory);
      expect((await harness.jobs.tools('job_1'))?.xcode, '27.1');
    });

    test('obfuscates and says where the debug info is', () async {
      final obfuscated = BuildIosInput(
        settings: BuildSettings(
          worktree: buildWorktree,
          version: AppVersion.parse('1.2.3+45'),
          flutterVersion: '3.47.6',
          obfuscate: true,
        ),
        exportOptionsPlist: 'ios/ExportOptions.plist',
      );

      final outcome = await step.run(obfuscated, context);

      expect(
        (outcome as StepSucceeded<BuildResult>).result.debugInfoDirectory,
        'build/xpath/debug-info/ios',
      );
    });

    test('clears the IPAs of earlier builds first', () async {
      harness.files.put(
        '$appDirectory/build/ios/ipa/Old.ipa',
        modified: harness.files.markedAt.subtract(const Duration(days: 1)),
      );

      final outcome = await step.run(input(), context);

      expect(outcome, isA<StepSucceeded<BuildResult>>());
      expect(harness.files.deleted, ['$appDirectory/build/ios/ipa/Old.ipa']);
    });

    test('fails when no IPA was exported', () async {
      context = BuildContext();

      final outcome = await step.run(input(), context);

      expect(
        (outcome as StepFailed).message,
        contains('no .ipa was found under $appDirectory/build'),
      );
    });

    test('fails when the build fails', () async {
      context = BuildContext(exit: const ProcessExit(exitCode: 65));

      final outcome = await step.run(input(), context);

      expect(
        (outcome as StepFailed).message,
        contains('flutter build ipa exited with code 65'),
      );
    });

    test('needs a Mac', () async {
      harness = BuildHarness();
      await harness.createJob();
      step = stepFor(isMacOS: false);

      final outcome = await step.run(input(), context);

      expect(
        (outcome as StepFailed).message,
        'build.ios needs macOS (ios-sign), or a Linux runner set up for iOS '
        'builds (ios-linux): this machine is neither. Run the job on a Mac.',
      );
      expect(context.commands, isEmpty);
    });
  });
}

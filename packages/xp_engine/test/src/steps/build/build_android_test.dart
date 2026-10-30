import 'dart:convert';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../helpers/build_harness.dart';

const _apk = '$appDirectory/build/app/outputs/flutter-apk/app-dev-release.apk';
const _aab =
    '$appDirectory/build/app/outputs/bundle/devRelease/app-dev-release.aab';

void main() {
  late BuildHarness harness;
  late BuildAndroidStep step;
  late BuildContext context;

  BuildAndroidInput input({
    ArtifactKind artifact = ArtifactKind.apk,
    bool obfuscate = false,
    String? flutterVersion = '3.47.6',
    String? dartDefineSecret,
  }) => BuildAndroidInput(
    settings: BuildSettings(
      worktree: buildWorktree,
      version: AppVersion.parse('1.2.3+45'),
      flavor: 'dev',
      target: 'lib/main_dev.dart',
      flutterVersion: flutterVersion,
      dartDefineSecret: dartDefineSecret,
      obfuscate: obfuscate,
      secretEnvironment: const {'KEYSTORE_PASSWORD': 'keystore.password'},
      secretFiles: const {'KEYSTORE_FILE': 'keystore.file'},
      passThroughEnvironment: const ['NDK_HOME'],
    ),
    artifact: artifact,
  );

  setUp(() async {
    harness = BuildHarness();
    await harness.createJob();
    step = BuildAndroidStep(
      toolchain: harness.toolchain,
      files: harness.files,
      recorder: harness.recorder,
      repository: harness.artifacts,
      store: harness.store,
    );
    // The build writes the APK after the marker.
    context = BuildContext(
      onRun: (_) => harness.files.put(_apk, bytes: utf8.encode('apk bytes')),
    );
  });

  group('the step', () {
    test('is build.android and has no side effect', () {
      expect(step.kind, 'build.android');
      expect(step.sideEffectOf(input()), isFalse);
    });

    test('stores its input as JSON', () {
      expect(step.decodeInput(step.encodeInput(input())), input());
      expect(step.encodeInput(input())['artifact'], 'apk');
      expect(
        step.decodeInput(step.encodeInput(input(artifact: ArtifactKind.aab))),
        input(artifact: ArtifactKind.aab),
      );
    });

    test('builds an APK unless told otherwise', () {
      final json = step.encodeInput(input())..remove('artifact');

      expect(step.decodeInput(json).artifact, ArtifactKind.apk);
    });

    test('refuses input that is not valid', () {
      final json = step.encodeInput(input());
      for (final bad in <Map<String, dynamic>>[
        {...json, 'artifact': 'ipa'},
        {...json, 'artifact': 3},
        {...json}..remove('version'),
      ]) {
        expect(() => step.decodeInput(bad), throwsFormatException);
      }
    });

    test('only builds an apk or an aab', () {
      expect(
        () => BuildAndroidInput(
          settings: input().settings,
          artifact: ArtifactKind.ipa,
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('run', () {
    test('builds the APK with the pinned Flutter and stores it', () async {
      final outcome = await step.run(input(), context);

      final result = (outcome as StepSucceeded<BuildResult>).result;
      expect(result.artifact.kind, ArtifactKind.apk);
      expect(result.artifact.name, 'dev-1.2.3+45.apk');
      expect(result.artifact.size, 9);
      expect(
        result.artifact.sha256,
        '9379cfb95416438572c33e2c2e03f1fdbdb10e4668cfbdb7bbd0e3049463ac33',
      );
      expect(result.flutter, '3.47.6');
      expect(result.dart, '3.13.5');
      expect(result.debugInfoDirectory, isNull);
      expect(
        harness.store.files['job_1/dev-1.2.3+45.apk'],
        utf8.encode('apk bytes'),
      );
      expect(
        (await harness.artifacts.forJob('job_1')).single.sha256,
        result.artifact.sha256,
      );
    });

    test('runs flutter build apk in the app, with secrets by name', () async {
      await step.run(input(), context);

      final command = context.commands.single;
      expect(command.executable, '/data/toolchains/flutter/3.47.6/bin/flutter');
      expect(command.arguments, [
        'build',
        'apk',
        '--release',
        '--flavor',
        'dev',
        '--target',
        'lib/main_dev.dart',
        '--build-name=1.2.3',
        '--build-number=45',
      ]);
      expect(command.workingDirectory, appDirectory);
      expect(command.environment, {'CI': 'true'});
      expect(command.secretEnvironment, {
        'KEYSTORE_PASSWORD': 'keystore.password',
      });
      expect(command.secretFiles, {'KEYSTORE_FILE': 'keystore.file'});
      expect(
        command.passThroughEnvironment,
        containsAll(['ANDROID_HOME', 'JAVA_HOME', 'NDK_HOME']),
      );
    });

    test('builds an app bundle for Google Play', () async {
      context = BuildContext(onRun: (_) => harness.files.put(_aab));

      final outcome = await step.run(
        input(artifact: ArtifactKind.aab),
        context,
      );

      expect(context.commands.single.arguments[1], 'appbundle');
      final result = (outcome as StepSucceeded<BuildResult>).result;
      expect(result.artifact.kind, ArtifactKind.aab);
      expect(result.artifact.name, 'dev-1.2.3+45.aab');
    });

    test('obfuscates and says where the debug info is', () async {
      final outcome = await step.run(input(obfuscate: true), context);

      expect(
        context.commands.single.arguments,
        containsAllInOrder([
          '--obfuscate',
          '--split-debug-info=build/xpath/debug-info/android',
        ]),
      );
      expect(
        (outcome as StepSucceeded<BuildResult>).result.debugInfoDirectory,
        'build/xpath/debug-info/android',
      );
    });

    test('records the tool versions of the job', () async {
      await step.run(input(), context);

      final tools = await harness.jobs.tools('job_1');
      expect(tools?.flutter, '3.47.6');
      expect(tools?.dart, '3.13.5');
    });

    test('fails when the app has no Flutter pin', () async {
      final outcome = await step.run(input(flutterVersion: null), context);

      expect(
        (outcome as StepFailed).message,
        contains('does not pin a Flutter version'),
      );
      expect(context.commands, isEmpty);
    });

    test('fails when the build fails', () async {
      context = BuildContext(exit: const ProcessExit(exitCode: 1));

      final outcome = await step.run(input(), context);

      expect(
        (outcome as StepFailed).message,
        'flutter build apk exited with code 1. The step log has its output.',
      );
      expect(await harness.artifacts.forJob('job_1'), isEmpty);
    });

    test('fails when the build is cancelled', () async {
      context = BuildContext(
        exit: const ProcessExit(exitCode: -15, cancelled: true),
      );

      final outcome = await step.run(input(), context);

      expect((outcome as StepFailed).message, 'The build was cancelled.');
    });

    test('refuses a leftover of an earlier build', () async {
      // The build "succeeds" without writing anything; an old APK is there.
      harness.files.put(
        _apk,
        modified: harness.files.markedAt.subtract(const Duration(days: 2)),
      );
      context = BuildContext();

      final outcome = await step.run(input(), context);

      expect(
        (outcome as StepFailed).message,
        contains('is older than this build'),
      );
      expect(outcome.message, contains(_apk));
      expect(await harness.artifacts.forJob('job_1'), isEmpty);
    });

    test('fails when the build produced no file', () async {
      context = BuildContext();

      final outcome = await step.run(input(), context);

      expect(
        (outcome as StepFailed).message,
        'flutter build succeeded but no .apk was found under '
        '$appDirectory/build.',
      );
    });

    test('keeps one artifact when it runs again', () async {
      await step.run(input(), context);
      final again = await step.run(input(), context);

      expect(again, isA<StepSucceeded<BuildResult>>());
      expect(await harness.artifacts.forJob('job_1'), hasLength(1));
    });
  });

  group('alreadyDone', () {
    test('is the artifact that is stored for the job', () async {
      final built = await step.run(input(), context);
      final result = (built as StepSucceeded<BuildResult>).result;

      final done = await step.alreadyDone(input(), context);

      expect(done?.artifact, result.artifact);
      expect(done?.flutter, '3.47.6');
      expect(done?.dart, '3.13.5');
    });

    test('is nothing before the build', () async {
      expect(await step.alreadyDone(input(), context), isNull);
    });

    test('is nothing when the file left the store', () async {
      await step.run(input(), context);
      harness.store.files.clear();

      expect(await step.alreadyDone(input(), context), isNull);
    });

    test('is nothing when the file no longer has its SHA-256', () async {
      await step.run(input(), context);
      harness.store.files['job_1/dev-1.2.3+45.apk'] = utf8.encode('tampered');

      expect(await step.alreadyDone(input(), context), isNull);
    });

    test('is nothing for another kind of package', () async {
      await step.run(input(), context);
      final record = (await harness.artifacts.forJob('job_1')).single;
      await harness.artifacts.save(
        ArtifactRecord(
          id: record.id,
          jobId: record.jobId,
          kind: ArtifactKind.aab,
          path: record.path,
          size: record.size,
          sha256: record.sha256,
          createdAt: record.createdAt,
        ),
      );

      expect(await step.alreadyDone(input(), context), isNull);
    });

    test('says where the debug info is for an obfuscated build', () async {
      await step.run(input(obfuscate: true), context);

      final done = await step.alreadyDone(input(obfuscate: true), context);

      expect(done?.debugInfoDirectory, 'build/xpath/debug-info/android');
    });
  });

  test('compares results by value', () async {
    final built = await step.run(input(), context);
    final result = (built as StepSucceeded<BuildResult>).result;

    expect(
      BuildResult(
        artifact: result.artifact,
        flutter: result.flutter,
        dart: result.dart,
      ),
      result,
    );
  });

  test('encodes its result', () async {
    final built = await step.run(input(), context);
    final result = (built as StepSucceeded<BuildResult>).result;

    expect(step.encodeResult(result), {
      'artifact': result.artifact.toJson(),
      'flutter': '3.47.6',
      'dart': '3.13.5',
    });
  });

  test('builds with the define file of a credential, by its path', () async {
    context.defines['defines'] = 'API_KEY=secret-value\n';

    final outcome = await step.run(input(dartDefineSecret: 'defines'), context);

    expect(outcome, isA<StepSucceeded<BuildResult>>());
    expect(context.secretFiles['dart-defines'], 'API_KEY=secret-value\n');
    final arguments = context.commands.single.arguments;
    expect(
      arguments,
      contains('--dart-define-from-file=/secrets/job_1/dart-defines'),
    );
    expect(arguments.join(' '), isNot(contains('secret-value')));
  });
}

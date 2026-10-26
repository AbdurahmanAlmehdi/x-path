import 'dart:convert';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../helpers/build_harness.dart';
import '../../../helpers/fake_build_directories.dart';

const _mapping =
    '$appDirectory/build/app/outputs/mapping/prodRelease/mapping.txt';
const _dsyms = '$appDirectory/build/ios/archive/Runner.xcarchive/dSYMs';
const _debugInfo = '$appDirectory/build/xpath/debug-info/ios';

void main() {
  late BuildHarness harness;
  late FakeBuildDirectories directories;
  late SymbolsArchiveStep step;
  late BuildContext context;

  SymbolsArchiveInput input({
    bool android = true,
    bool ios = true,
    String? debugInfo = 'build/xpath/debug-info/ios',
    String? flavor = 'prod',
  }) => SymbolsArchiveInput(
    settings: BuildSettings(
      worktree: buildWorktree,
      version: AppVersion.parse('1.2.3+45'),
      flavor: flavor,
    ),
    android: android,
    ios: ios,
    debugInfoDirectory: debugInfo,
  );

  setUp(() {
    harness = BuildHarness();
    directories = FakeBuildDirectories();
    step = SymbolsArchiveStep(
      directories: directories,
      files: harness.files,
      recorder: harness.recorder,
      repository: harness.artifacts,
      store: harness.store,
    );
    context = BuildContext();
    harness.files.put(_mapping, bytes: utf8.encode('a -> b:'));
    directories.folders
      ..[_dsyms] = 10
      ..[_debugInfo] = 20;
  });

  group('the step', () {
    test('is symbols.archive and has no side effect', () {
      expect(step.kind, 'symbols.archive');
      expect(step.sideEffectOf(input()), isFalse);
    });

    test('stores its input as JSON', () {
      expect(step.decodeInput(step.encodeInput(input())), input());
      expect(
        step.decodeInput(
          step.encodeInput(input(android: false, ios: false, debugInfo: null)),
        ),
        input(android: false, ios: false, debugInfo: null),
      );
    });

    test('keeps nothing unless told', () {
      final json = step.encodeInput(input())
        ..remove('android')
        ..remove('ios')
        ..remove('debugInfoDirectory');

      final decoded = step.decodeInput(json);
      expect(decoded.android, isFalse);
      expect(decoded.ios, isFalse);
      expect(decoded.debugInfoDirectory, isNull);
    });

    test('refuses a debug info folder outside the app', () {
      final json = step.encodeInput(input())..['debugInfoDirectory'] = '../x';

      expect(() => step.decodeInput(json), throwsFormatException);
    });

    test('encodes its result', () {
      final warnings = ['w'];
      final result = SymbolsArchiveResult(
        artifacts: const [],
        warnings: warnings,
      );

      expect(step.encodeResult(result), {
        'artifacts': <Object?>[],
        'warnings': ['w'],
      });
      expect(
        result,
        const SymbolsArchiveResult(artifacts: [], warnings: ['w']),
      );
    });
  });

  group('run', () {
    test('stores the mapping, the dSYMs and the debug info', () async {
      final outcome = await step.run(input(), context);

      final result = (outcome as StepSucceeded<SymbolsArchiveResult>).result;
      expect(result.warnings, isEmpty);
      expect(
        result.artifacts.map((artifact) => (artifact.kind, artifact.name)),
        [
          (ArtifactKind.mapping, 'prod-1.2.3+45.mapping.txt'),
          (ArtifactKind.dsym, 'prod-1.2.3+45.dSYMs.zip'),
          (ArtifactKind.shorebirdSymbols, 'prod-1.2.3+45.debug-info.zip'),
        ],
      );
      expect(
        harness.store.files['job_1/prod-1.2.3+45.mapping.txt'],
        utf8.encode('a -> b:'),
      );
      expect(harness.store.files['job_1/prod-1.2.3+45.dSYMs.zip'], [
        80,
        75,
        3,
        4,
      ]);
      expect(directories.zips, [_dsyms, _debugInfo]);
      expect(
        (await harness.artifacts.forJob('job_1')).map((r) => r.sha256),
        result.artifacts.map((artifact) => artifact.sha256),
      );
    });

    test('takes the dSYMs a Linux build left (ADR 0014)', () async {
      const linux = '$appDirectory/build/ios-linux/dSYMs';
      directories.folders
        ..remove(_dsyms)
        ..[linux] = 5;

      final outcome = await step.run(
        input(android: false, debugInfo: null),
        context,
      );

      final result = (outcome as StepSucceeded<SymbolsArchiveResult>).result;
      expect(result.artifacts.single.name, 'prod-1.2.3+45.dSYMs.zip');
      expect(directories.zips, [linux]);
    });

    test('finds the mapping of an app without flavors', () async {
      harness.files.put(
        '$appDirectory/build/app/outputs/mapping/release/mapping.txt',
      );

      final outcome = await step.run(
        input(ios: false, debugInfo: null, flavor: null),
        context,
      );

      final result = (outcome as StepSucceeded<SymbolsArchiveResult>).result;
      expect(result.artifacts.single.name, 'app-1.2.3+45.mapping.txt');
    });

    test('warns about what is not there, and keeps the rest', () async {
      harness.files.files.clear();
      directories.folders.remove(_dsyms);
      directories.folders.remove(_debugInfo);

      final outcome = await step.run(input(), context);

      final result = (outcome as StepSucceeded<SymbolsArchiveResult>).result;
      expect(result.artifacts, isEmpty);
      expect(result.warnings, [
        contains('No R8 mapping at build/app/outputs/mapping/prodRelease'),
        contains(
          'No dSYMs in build/ios/archive/Runner.xcarchive/dSYMs or '
          'build/ios-linux/dSYMs',
        ),
        contains('No debug info in build/xpath/debug-info/ios'),
      ]);
      expect(result.warnings.first, contains('1.2.3+45 may be unbuildable'));
    });

    test('skips when nothing was asked for', () async {
      final outcome = await step.run(
        input(android: false, ios: false, debugInfo: null),
        context,
      );

      expect(outcome, isA<StepSkipped>());
    });

    test('replaces the artifacts when it runs again', () async {
      await step.run(input(), context);
      final first = await harness.artifacts.forJob('job_1');
      harness.files.put(_mapping, bytes: utf8.encode('changed'));

      await step.run(input(), context);

      final second = await harness.artifacts.forJob('job_1');
      expect(second, hasLength(3));
      expect(second.first.id, first.first.id);
      expect(second.first.sha256, isNot(first.first.sha256));
    });
  });

  group('alreadyDone', () {
    test('is not done before anything was stored', () async {
      expect(await step.alreadyDone(input(), context), isNull);
    });

    test('is done when everything that can be found is stored', () async {
      await step.run(input(), context);

      final done = await step.alreadyDone(input(), context);

      expect(done!.artifacts, hasLength(3));
    });

    test('is done when what was not there is still not there', () async {
      directories.folders.clear();
      await step.run(input(), context);

      final done = await step.alreadyDone(input(), context);

      expect(done!.artifacts.single.kind, ArtifactKind.mapping);
    });

    test('is not done when a symbol appeared since', () async {
      await step.run(input(ios: false, debugInfo: null), context);

      expect(await step.alreadyDone(input(), context), isNull);
    });

    test('is not done when a stored file changed', () async {
      await step.run(input(), context);
      harness.store.files['job_1/prod-1.2.3+45.mapping.txt'] = [1];

      expect(await step.alreadyDone(input(), context), isNull);
    });

    test('is not done when there is nothing to keep', () async {
      expect(
        await step.alreadyDone(
          input(android: false, ios: false, debugInfo: null),
          context,
        ),
        isNull,
      );
    });
  });
}

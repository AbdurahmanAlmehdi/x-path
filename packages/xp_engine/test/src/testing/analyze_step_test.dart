import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/build_harness.dart';
import '../../helpers/streaming_context.dart';
import '../../helpers/testing_fixtures.dart';

void main() {
  late BuildHarness harness;
  late AnalyzeStep step;

  setUp(() async {
    harness = BuildHarness();
    await harness.createJob();
    step = AnalyzeStep(toolchain: harness.toolchain);
  });

  AnalyzeInput input({
    AnalyzeSeverity failOn = AnalyzeSeverity.error,
    String? flutterVersion = '3.47.6',
  }) => AnalyzeInput(
    worktree: buildWorktree,
    flutterVersion: flutterVersion,
    failOn: failOn,
  );

  /// `flutter pub get` succeeds; `flutter analyze` prints the captured output
  /// (issues on standard output, the summary on standard error).
  StreamingContext analyzing(
    String fixture, {
    ProcessExit exit = const ProcessExit(exitCode: 1),
  }) {
    final lines = fixtureLines(fixture);
    final summary = lines.where(
      (line) => line.contains('issue') && line.contains('found'),
    );
    return StreamingContext(
      (command, index) => index == 0
          ? (
              stdout: const [],
              stderr: const [],
              exit: const ProcessExit(exitCode: 0),
            )
          : (
              stdout: lines.where((line) => !summary.contains(line)).toList(),
              stderr: summary.toList(),
              exit: exit,
            ),
    );
  }

  group('the step', () {
    test('is analyze and has no side effect', () {
      expect(step.kind, 'analyze');
      expect(step.sideEffectOf(input()), isFalse);
    });

    test('stores its input as JSON', () {
      final warnings = input(failOn: AnalyzeSeverity.warning);

      expect(step.decodeInput(step.encodeInput(warnings)), warnings);
      expect(step.encodeInput(input())['failOn'], 'error');
    });

    test('fails on errors unless told otherwise', () {
      final json = step.encodeInput(input())..remove('failOn');

      expect(step.decodeInput(json).failOn, AnalyzeSeverity.error);
    });

    test('refuses input that is not valid', () {
      final json = step.encodeInput(input());
      for (final bad in <Map<String, dynamic>>[
        {...json, 'failOn': 'hint'},
        {...json, 'failOn': 3},
        {...json}..remove('worktree'),
      ]) {
        expect(() => step.decodeInput(bad), throwsFormatException);
      }
    });

    test('stores its result as JSON', () {
      const issue = AnalyzeIssue(
        severity: AnalyzeSeverity.warning,
        message: 'm',
        path: 'lib/a.dart',
        line: 1,
        column: 2,
        code: 'c',
      );
      const result = AnalyzeResult(
        errors: 0,
        warnings: 1,
        infos: 0,
        issues: [issue],
      );

      expect(step.encodeResult(result), {
        'errors': 0,
        'warnings': 1,
        'infos': 0,
        'truncated': false,
        'issues': [issue.toJson()],
      });
      expect(result.props, hasLength(4));
      expect(const AnalyzeReport(issues: [issue], reported: 1).props, [
        const [issue],
        1,
      ]);
    });

    test('knows the app directory', () {
      expect(input().appDirectory, appDirectory);
      expect(
        const AnalyzeInput(
          worktree: ReleaseWorktree(
            path: '/work/job_1',
            mirror: GitMirror(githubRepoId: 42, path: '/m.git'),
            sha: buildSha,
          ),
        ).appDirectory,
        '/work/job_1',
      );
    });
  });

  group('analyzing', () {
    test('resolves packages, then analyzes without pub', () async {
      final context = analyzing(
        'analyze_clean.txt',
        exit: const ProcessExit(exitCode: 0),
      );

      await step.run(input(), context);

      expect(context.commands.map((command) => command.arguments), [
        ['pub', 'get'],
        ['analyze', '--no-pub', '--no-fatal-infos', '--no-fatal-warnings'],
      ]);
      for (final command in context.commands) {
        expect(
          command.executable,
          '/data/toolchains/flutter/3.47.6/bin/flutter',
        );
        expect(command.workingDirectory, appDirectory);
        expect(command.environment, {'CI': 'true'});
        expect(command.passThroughEnvironment, AnalyzeStep.environmentNames);
      }
      expect((await harness.jobs.tools('job_1'))?.flutter, '3.47.6');
    });

    test('succeeds on a clean app', () async {
      final outcome = await step.run(
        input(),
        analyzing('analyze_clean.txt', exit: const ProcessExit(exitCode: 0)),
      );

      final result = (outcome as StepSucceeded<AnalyzeResult>).result;
      expect((result.errors, result.warnings, result.infos), (0, 0, 0));
    });

    test('fails on errors and names them', () async {
      final outcome = await step.run(input(), analyzing('analyze_issues.txt'));

      expect(
        (outcome as StepFailed).message,
        'flutter analyze found 2 errors:\n'
        "lib/main.dart:6:10: Undefined name 'undefinedName'. Try correcting "
        'the name to one that is defined, or defining the name '
        '(undefined_identifier)\n'
        "lib/main.dart:15:27: A value of type 'int' can't be returned from "
        "the function 'takesInt' because it has a return type of 'String' "
        '(return_of_invalid_type)',
      );
    });

    test('records warnings and lints without failing on them', () async {
      final lines = fixtureLines('analyze_issues.txt')
          .where((line) => !line.contains('error •'))
          .map((line) => line.contains('found.') ? '2 issues found.' : line)
          .toList();

      final outcome = await step.run(input(), StreamingContext.single(lines));

      final result = (outcome as StepSucceeded<AnalyzeResult>).result;
      expect((result.errors, result.warnings, result.infos), (0, 1, 1));
      expect(result.issues.first.code, 'unused_local_variable');
    });

    test('fails on warnings when told to', () async {
      final lines = fixtureLines('analyze_issues.txt')
          .where((line) => !line.contains('error •'))
          .map((line) => line.contains('found.') ? '2 issues found.' : line)
          .toList();

      final outcome = await step.run(
        input(failOn: AnalyzeSeverity.warning),
        StreamingContext.single(lines),
      );

      expect(
        (outcome as StepFailed).message,
        startsWith('flutter analyze found 1 errors or warnings:\n'),
      );
    });

    test('fails on any issue when told to, and counts the rest', () async {
      final lines = [
        for (var i = 1; i <= 8; i++)
          '   info • Lint $i • lib/a.dart:$i:1 • rule',
        '8 issues found.',
      ];

      final outcome = await step.run(
        input(failOn: AnalyzeSeverity.info),
        StreamingContext.single(lines),
      );

      final message = (outcome as StepFailed).message.split('\n');
      expect(message.first, 'flutter analyze found 8 issues:');
      expect(message, hasLength(1 + 5 + 1));
      expect(message.last, 'and 3 more.');
    });
  });

  group('an analysis that cannot be trusted', () {
    test('fails when the SDK cannot be resolved', () async {
      final outcome = await step.run(
        input(flutterVersion: null),
        analyzing('analyze_clean.txt'),
      );

      expect(
        (outcome as StepFailed).message,
        contains('does not pin a Flutter version'),
      );
    });

    test('fails when packages cannot be resolved', () async {
      final context = StreamingContext.single(
        const [],
        exit: const ProcessExit(exitCode: 1),
      );

      final outcome = await step.run(input(), context);

      expect(
        (outcome as StepFailed).message,
        'flutter pub get exited with code 1. The step log has its output.',
      );
      expect(context.commands, hasLength(1));
    });

    test('fails when it is cancelled while resolving packages', () async {
      final outcome = await step.run(
        input(),
        StreamingContext.single(
          const [],
          exit: const ProcessExit(exitCode: -15, cancelled: true),
        ),
      );

      expect((outcome as StepFailed).message, 'The analysis was cancelled.');
    });

    test('fails when it is cancelled while analyzing', () async {
      final outcome = await step.run(
        input(),
        StreamingContext(
          (command, index) => (
            stdout: const [],
            stderr: const [],
            exit: index == 0
                ? const ProcessExit(exitCode: 0)
                : const ProcessExit(exitCode: -15, cancelled: true),
          ),
        ),
      );

      expect((outcome as StepFailed).message, 'The analysis was cancelled.');
    });

    test('fails when the analyzer prints no summary', () async {
      final outcome = await step.run(
        input(),
        StreamingContext(
          (command, index) => (
            stdout: const ['Analyzing app...'],
            stderr: const ['Unhandled exception: boom'],
            exit: ProcessExit(exitCode: index == 0 ? 0 : 3),
          ),
        ),
      );

      expect(
        (outcome as StepFailed).message,
        'flutter analyze did not finish (exit code 3). The step log has its '
        'output.',
      );
    });

    test('fails when it announces issues it cannot read', () async {
      final outcome = await step.run(
        input(),
        StreamingContext(
          (command, index) => (
            stdout: const ['error • no location here'],
            stderr: const ['1 issue found.'],
            exit: ProcessExit(exitCode: index == 0 ? 0 : 1),
          ),
        ),
      );

      expect(
        (outcome as StepFailed).message,
        startsWith('flutter analyze announced 1 issues but 0 could be read'),
      );
    });
  });
}

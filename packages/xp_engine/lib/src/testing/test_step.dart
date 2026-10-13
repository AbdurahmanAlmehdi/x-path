import 'dart:math';

import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/clock/clock.dart';
import 'package:xp_engine/src/jobs/job_repository.dart';
import 'package:xp_engine/src/process/process_supervisor.dart';
import 'package:xp_engine/src/repositories/event_log.dart';
import 'package:xp_engine/src/steps/build/build_toolchain.dart';
import 'package:xp_engine/src/steps/step.dart';
import 'package:xp_engine/src/steps/step_context.dart';
import 'package:xp_engine/src/testing/machine_test_parser.dart';
import 'package:xp_engine/src/testing/test_evaluation.dart';
import 'package:xp_engine/src/testing/test_input.dart';
import 'package:xp_engine/src/testing/test_run_diff.dart';
import 'package:xp_engine/src/testing/test_run_record.dart';
import 'package:xp_engine/src/testing/test_run_repository.dart';
import 'package:xp_engine/src/testing/test_step_result.dart';
import 'package:xp_engine/src/toolchain/flutter_resolver.dart';

/// How many new failures the failure message of the step names.
const _namedFailures = 5;

/// Runs the tests of the app and judges them against the baseline (`test`,
/// D-21).
///
/// Runs `flutter test --machine` of the job's pinned Flutter SDK in the app
/// and reads the JSON events as they arrive into one result per test. The
/// step stores the run (one per job) and fails only on tests that fail now and
/// did not fail in the baseline: the last green run of the base branch. Other
/// failures are what the project lives with. It also fails when the run did
/// not finish, printed no machine output or ran no test at all, since none of
/// those says the code is fine.
///
/// A complete run of the base branch with no new failures becomes the
/// baseline. The first run of the base branch seeds it.
class TestStep extends Step<TestInput, TestStepResult> {
  /// Creates the step. [random] is for tests; it must be cryptographically
  /// secure otherwise.
  new({
    required this.toolchain,
    required this.jobs,
    required this.runs,
    required this.events,
    required this.clock,
    Random? random,
  }) : _random = random ?? Random.secure();

  /// Resolves Flutter and records the tool versions.
  final BuildToolchain toolchain;

  /// The jobs, to know which project a job belongs to.
  final JobRepository jobs;

  /// The stored test runs.
  final TestRunRepository runs;

  /// Hears about the finished run.
  final EventLog events;

  /// The time of the run.
  final Clock clock;

  final Random _random;

  /// The variables of the engine's environment that `flutter test` reads on
  /// top of the allowed ones.
  static const environmentNames = [
    'PUB_CACHE',
    'PUB_HOSTED_URL',
    'FLUTTER_STORAGE_BASE_URL',
  ];

  @override
  String get kind => 'test';

  @override
  bool sideEffectOf(TestInput input) => false;

  @override
  TestInput decodeInput(Map<String, dynamic> json) => TestInput.fromJson(json);

  @override
  Map<String, dynamic> encodeInput(TestInput input) => input.toJson();

  @override
  Map<String, dynamic> encodeResult(TestStepResult result) => result.toJson();

  @override
  Future<StepOutcome<TestStepResult>> run(
    TestInput input,
    StepContext context,
  ) async {
    final job = await jobs.get(context.jobId);
    if (job == null) return StepFailed('There is no job ${context.jobId}.');
    final ResolvedFlutter flutter;
    try {
      flutter = await toolchain.prepare(context.jobId, input.flutterVersion);
    } on ToolchainException catch (error) {
      return StepFailed(error.message);
    }

    final parser = MachineTestParser(appDirectory: input.appDirectory);
    final exit = await context.run(
      ProcessCommand(
        flutter.flutterExecutable,
        arguments: [
          'test',
          '--machine',
          if (input.tags.isNotEmpty) ...['--tags', _tagSelector(input.tags)],
          ...input.paths,
        ],
        workingDirectory: input.appDirectory,
        environment: const {'CI': 'true'},
        passThroughEnvironment: environmentNames,
      ),
      onLine: (line) {
        if (line.stream == LogStream.stdout) parser.addLine(line.text);
      },
    );
    if (exit.cancelled) return const StepFailed('The tests were cancelled.');
    final parsed = parser.finish();
    if (parsed == null) {
      return StepFailed(
        parser.events == 0
            ? 'flutter test printed no machine output (exit code '
                  '${exit.exitCode}). The step log has what it printed.'
            : 'flutter test stopped before the run was over (exit code '
                  '${exit.exitCode}), so its results cannot be trusted. The '
                  'step log has its output.',
      );
    }
    final results = parsed.results;
    if (results.tests.isEmpty) {
      return const StepFailed(
        'flutter test ran no tests, so nothing was tested. Check the paths '
        'and tags of the step.',
      );
    }

    final baseline = await runs.baseline(
      projectId: job.projectId,
      appPath: input.worktree.appPath,
      branch: input.baseBranch,
    );
    final evaluation = evaluateTestRun(
      results: results,
      baseline: baseline,
      onBaseBranch: input.branch == input.baseBranch,
      filtered: input.filtered,
      expected: input.tags.isNotEmpty
          ? ExpectedTests.none
          : input.paths.isNotEmpty
          ? ExpectedTests.ranSuites
          : ExpectedTests.all,
    );
    final diff = evaluation.diff;
    final record = TestRunRecord(
      id: (await runs.forJob(context.jobId))?.id ?? 'tst_${_hex(8)}',
      jobId: context.jobId,
      projectId: job.projectId,
      branch: input.branch,
      appPath: input.worktree.appPath,
      baseline: evaluation.becomesBaseline,
      createdAt: clock.now(),
      results: results,
      diff: diff,
    );
    await runs.save(record);
    final counts = results.counts;
    events.append(
      TestRunCompleted(
        jobId: context.jobId,
        projectId: job.projectId,
        branch: input.branch,
        baseline: record.baseline,
        failures: counts.failed + counts.errored,
        newFailures: diff.newFailures.length,
      ),
    );

    if (evaluation.failsStep) {
      return StepFailed(_failureMessage(diff, baseline == null, input));
    }
    return StepSucceeded(
      TestStepResult(
        runId: record.id,
        counts: counts,
        newFailures: diff.newFailures.length,
        fixed: diff.fixed.length,
        missing: diff.missing.length,
        stillFailing: diff.stillFailing,
        baseline: record.baseline,
        seeded: evaluation.seeded,
        comparedTo: diff.comparedTo,
      ),
    );
  }

  /// One selector for `--tags`, which takes a single boolean expression:
  /// a test must match all of [tags].
  String _tagSelector(List<String> tags) =>
      tags.length == 1 ? tags.single : tags.map((tag) => '($tag)').join(' && ');

  String _failureMessage(TestRunDiff diff, bool noBaseline, TestInput input) {
    final named = [
      for (final test in diff.newFailures.take(_namedFailures))
        '${test.suite}: ${test.name}',
    ];
    final more = diff.newFailures.length - named.length;
    final count = diff.newFailures.length;
    final headline = noBaseline
        ? '$count tests fail and there is no baseline yet. Run the tests on '
              '${input.baseBranch} first: the first run there becomes the '
              'baseline.'
        : '$count ${count == 1 ? 'test fails' : 'tests fail'} that did not '
              'fail in the baseline (job ${diff.comparedTo}).';
    return [headline, ...named, if (more > 0) 'and $more more.'].join('\n');
  }

  String _hex(int bytes) => List.generate(
    bytes,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

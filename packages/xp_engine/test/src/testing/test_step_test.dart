import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/build_harness.dart';
import '../../helpers/streaming_context.dart';
import '../../helpers/testing_fixtures.dart';

/// The worktree whose app directory is the one the captured runs were made in.
const _worktree = ReleaseWorktree(
  path: '/work',
  mirror: GitMirror(githubRepoId: 42, path: '/mirrors/42.git'),
  sha: buildSha,
  appPath: 'app',
);

void main() {
  late BuildHarness harness;
  late InMemoryTestRunRepository runs;
  late InMemoryEventLog events;
  late TestStep step;

  setUp(() async {
    harness = BuildHarness();
    await harness.createJob();
    runs = InMemoryTestRunRepository();
    events = InMemoryEventLog(clock: harness.clock);
    step = TestStep(
      toolchain: harness.toolchain,
      jobs: harness.jobs,
      runs: runs,
      events: events,
      clock: harness.clock,
      random: ZeroRandom(),
    );
  });

  TestInput input({
    String branch = 'main',
    String baseBranch = 'main',
    String? flutterVersion = '3.47.6',
    List<String> paths = const [],
    List<String> tags = const [],
  }) => TestInput(
    worktree: _worktree,
    branch: branch,
    baseBranch: baseBranch,
    flutterVersion: flutterVersion,
    paths: paths,
    tags: tags,
  );

  Future<void> startJob(String id) => harness.jobs.create(
    JobRecord(
      id: id,
      workflowVersionId: 'wfv_1',
      projectId: 'prj_1',
      state: JobState.running,
      createdAt: harness.clock.now(),
    ),
    const [],
  );

  StreamingContext printing(
    String fixture, {
    String jobId = 'job_1',
    ProcessExit exit = const ProcessExit(exitCode: 1),
  }) =>
      StreamingContext.single(fixtureLines(fixture), exit: exit, jobId: jobId);

  group('the step', () {
    test('is test and has no side effect', () {
      expect(step.kind, 'test');
      expect(step.sideEffectOf(input()), isFalse);
    });

    test('stores its input as JSON', () {
      final full = input(
        branch: 'feat/x',
        paths: const ['test/a_test.dart'],
        tags: const ['fast'],
      );

      expect(step.decodeInput(step.encodeInput(full)), full);
      expect(step.decodeInput(step.encodeInput(input())), input());
    });

    test('stores its result as JSON', () async {
      final outcome = await step.run(
        input(),
        printing('baseline_27_failures.jsonl'),
      );
      final result = (outcome as StepSucceeded<TestStepResult>).result;

      expect(step.encodeResult(result), {
        'runId': result.runId,
        'counts': {
          'total': 48,
          'passed': 19,
          'failed': 25,
          'errored': 2,
          'skipped': 2,
        },
        'newFailures': 27,
        'fixed': 0,
        'missing': 0,
        'stillFailing': 0,
        'baseline': true,
        'seeded': true,
      });
      expect(
        step.encodeResult(
          TestStepResult(
            runId: result.runId,
            counts: result.counts,
            newFailures: 0,
            fixed: 1,
            missing: 2,
            stillFailing: 3,
            baseline: false,
            seeded: false,
            comparedTo: 'job_0',
          ),
        )['comparedTo'],
        'job_0',
      );
      expect(result.props, hasLength(9));
    });

    test('gives a run a random id', () async {
      step = TestStep(
        toolchain: harness.toolchain,
        jobs: harness.jobs,
        runs: runs,
        events: events,
        clock: harness.clock,
      );

      await step.run(input(), printing('baseline_27_failures.jsonl'));

      expect((await runs.forJob('job_1'))?.id, matches(r'^tst_[0-9a-f]{16}$'));
    });

    test('refuses input that is not valid', () {
      final json = step.encodeInput(input());
      for (final bad in <Map<String, dynamic>>[
        {...json}..remove('branch'),
        {...json}..remove('baseBranch'),
        {...json}..remove('worktree'),
        {
          ...json,
          'paths': ['../outside'],
        },
        {
          ...json,
          'paths': ['/abs/test'],
        },
        {
          ...json,
          'paths': ['--coverage'],
        },
        {
          ...json,
          'paths': [''],
        },
        {
          ...json,
          'tags': [''],
        },
        {
          ...json,
          'tags': ['--name'],
        },
        {...json, 'paths': 'test/a_test.dart'},
      ]) {
        expect(() => step.decodeInput(bad), throwsFormatException);
      }
    });

    test('knows its app directory, and when it runs only some tests', () {
      expect(input().appDirectory, '/work/app');
      expect(input().filtered, isFalse);
      expect(input(paths: const ['test/a_test.dart']).filtered, isTrue);
      expect(input(tags: const ['fast']).filtered, isTrue);
      expect(
        const TestInput(
          worktree: ReleaseWorktree(
            path: '/work',
            mirror: GitMirror(githubRepoId: 42, path: '/m.git'),
            sha: buildSha,
          ),
          branch: 'main',
          baseBranch: 'main',
        ).appDirectory,
        '/work',
      );
    });
  });

  group('running the tests', () {
    test('runs flutter test --machine of the pinned SDK in the app', () async {
      final context = printing('baseline_27_failures.jsonl');

      await step.run(
        input(
          paths: const ['test/a_test.dart', 'test/b'],
          tags: const ['x', 'y || z'],
        ),
        context,
      );

      final command = context.commands.single;
      expect(command.executable, '/data/toolchains/flutter/3.47.6/bin/flutter');
      expect(command.arguments, [
        'test',
        '--machine',
        '--tags',
        '(x) && (y || z)',
        'test/a_test.dart',
        'test/b',
      ]);
      expect(command.workingDirectory, '/work/app');
      expect(command.environment, {'CI': 'true'});
      expect(command.passThroughEnvironment, TestStep.environmentNames);
    });

    test('passes a single tag as it is', () async {
      final context = printing('baseline_27_failures.jsonl');

      await step.run(input(tags: const ['fast']), context);

      expect(context.commands.single.arguments, [
        'test',
        '--machine',
        '--tags',
        'fast',
      ]);
    });

    test('records the tool versions of the job', () async {
      await step.run(input(), printing('baseline_27_failures.jsonl'));

      expect((await harness.jobs.tools('job_1'))?.flutter, '3.47.6');
    });

    test('reads only what the command prints on standard output', () async {
      final context = StreamingContext.single(
        const [],
        stderr: fixtureLines('baseline_27_failures.jsonl'),
      );

      final outcome = await step.run(input(), context);

      expect((outcome as StepFailed).message, contains('no machine output'));
    });
  });

  group('the baseline', () {
    test(
      'the first run of the base branch seeds it, failures and all',
      () async {
        final outcome = await step.run(
          input(),
          printing('baseline_27_failures.jsonl'),
        );

        final result = (outcome as StepSucceeded<TestStepResult>).result;
        expect(result.counts.failed + result.counts.errored, 27);
        expect(result.baseline, isTrue);
        expect(result.seeded, isTrue);
        expect(result.newFailures, 27);
        expect(result.comparedTo, isNull);
        final run = await runs.forJob('job_1');
        expect(run?.baseline, isTrue);
        expect(run?.branch, 'main');
        expect(run?.appPath, 'app');
        expect(run?.projectId, 'prj_1');
        expect(run?.id, 'tst_${'00' * 8}');
        expect(result.runId, run?.id);
      },
    );

    test('a branch with only the old failures passes', () async {
      await step.run(input(), printing('baseline_27_failures.jsonl'));
      await startJob('job_2');

      final outcome = await step.run(
        input(branch: 'feat/x'),
        printing('baseline_27_failures.jsonl', jobId: 'job_2'),
      );

      final result = (outcome as StepSucceeded<TestStepResult>).result;
      expect(result.newFailures, 0);
      expect(result.stillFailing, 27);
      expect(result.baseline, isFalse);
      expect(result.seeded, isFalse);
      expect(result.comparedTo, 'job_1');
      expect((await runs.forJob('job_2'))?.baseline, isFalse);
    });

    test('a branch fails on the new failures only, and says which', () async {
      await step.run(input(), printing('baseline_27_failures.jsonl'));
      await startJob('job_2');

      final outcome = await step.run(
        input(branch: 'feat/x'),
        printing('branch_run.jsonl', jobId: 'job_2'),
      );

      expect(
        (outcome as StepFailed).message,
        '3 tests fail that did not fail in the baseline (job job_1).\n'
        'test/async_test.dart: async success 5\n'
        'test/math_test.dart: subtraction subtracts one\n'
        'test/math_test.dart: subtraction subtracts two',
      );
      final run = await runs.forJob('job_2');
      expect(run?.diff.newFailures, hasLength(3));
      expect(run?.diff.fixed, hasLength(1));
      expect(run?.diff.missing, hasLength(1));
      expect(run?.baseline, isFalse);
    });

    test('names the first few new failures and counts the rest', () async {
      await step.run(input(), printing('load_and_setup_failures.jsonl'));
      await startJob('job_2');
      await step.run(
        input(),
        printing('load_and_setup_failures.jsonl', jobId: 'job_2'),
      );
      await startJob('job_3');

      // The 27 failing tests are all new against that baseline.
      final outcome = await step.run(
        input(branch: 'feat/x'),
        printing('baseline_27_failures.jsonl', jobId: 'job_3'),
      );

      final lines = (outcome as StepFailed).message.split('\n');
      expect(lines.first, startsWith('27 tests fail that did not fail'));
      expect(lines, hasLength(1 + 5 + 1));
      expect(lines.last, 'and 22 more.');
    });

    test('says so when a single test is new', () async {
      await step.run(input(), printing('baseline_27_failures.jsonl'));
      await startJob('job_2');
      final lines = fixtureLines('branch_run.jsonl')
          .where((line) => !line.contains('subtract'))
          .toList();

      final outcome = await step.run(
        input(branch: 'feat/x'),
        StreamingContext.single(lines, jobId: 'job_2'),
      );

      // Without the two subtraction tests, one failure is new.
      expect(
        (outcome as StepFailed).message,
        startsWith('1 test fails that did not fail in the baseline'),
      );
    });

    test(
      'a branch without a baseline is told to run the base branch',
      () async {
        final outcome = await step.run(
          input(branch: 'feat/x'),
          printing('load_and_setup_failures.jsonl'),
        );

        expect(
          (outcome as StepFailed).message,
          startsWith(
            '2 tests fail and there is no baseline yet. Run the tests on main '
            'first: the first run there becomes the baseline.',
          ),
        );
      },
    );

    test('a green run of the base branch becomes the new baseline', () async {
      await step.run(input(), printing('baseline_27_failures.jsonl'));
      await startJob('job_2');

      final outcome = await step.run(
        input(),
        printing('baseline_27_failures.jsonl', jobId: 'job_2'),
      );

      final result = (outcome as StepSucceeded<TestStepResult>).result;
      expect(result.baseline, isTrue);
      expect(result.seeded, isFalse);
      expect(
        (await runs.baseline(
          projectId: 'prj_1',
          appPath: 'app',
          branch: 'main',
        ))?.jobId,
        'job_2',
      );
    });

    test('a run of some files is no baseline', () async {
      final outcome = await step.run(
        input(paths: const ['test/math_test.dart']),
        printing('baseline_27_failures.jsonl'),
      );

      expect(outcome, isA<StepFailed>());
      expect((await runs.forJob('job_1'))?.baseline, isFalse);
    });

    test('only counts tests missing where the run should have them', () async {
      await step.run(input(), printing('baseline_27_failures.jsonl'));
      await startJob('job_2');
      await startJob('job_3');
      await startJob('job_4');
      final base = fixtureLines('baseline_27_failures.jsonl');
      // A run that reports one file only.
      final math = base
          .where((line) => !line.contains('strings_test'))
          .toList();

      await step.run(
        input(branch: 'feat/x', paths: const ['test/math_test.dart']),
        StreamingContext.single(math, jobId: 'job_2'),
      );
      await step.run(
        input(branch: 'feat/x', tags: const ['fast']),
        StreamingContext.single(math, jobId: 'job_3'),
      );
      await step.run(
        input(branch: 'feat/x'),
        StreamingContext.single(math, jobId: 'job_4'),
      );

      final missing = [
        for (final job in ['job_2', 'job_3', 'job_4'])
          (await runs.forJob(job))!.diff.missing.length,
      ];
      expect(missing[0], lessThan(missing[2]));
      expect(missing[1], 0);
      expect(missing[0], 0);
      expect(missing[2], greaterThan(0));
    });

    test('running the step again replaces the run of the job', () async {
      await step.run(input(), printing('baseline_27_failures.jsonl'));
      final first = await runs.forJob('job_1');

      await step.run(input(), printing('baseline_27_failures.jsonl'));

      expect((await runs.forJob('job_1'))?.id, first?.id);
      expect(await runs.baselines('prj_1'), hasLength(1));
    });
  });

  group('the event', () {
    test('tells that a run completed, with its numbers', () async {
      await step.run(input(), printing('baseline_27_failures.jsonl'));
      await startJob('job_2');

      await step.run(
        input(branch: 'feat/x'),
        printing('branch_run.jsonl', jobId: 'job_2'),
      );

      final logged = await events.subscribe(after: 0).take(2).toList();
      expect(logged.map((event) => event.event), [
        const TestRunCompleted(
          jobId: 'job_1',
          projectId: 'prj_1',
          branch: 'main',
          baseline: true,
          failures: 27,
          newFailures: 27,
        ),
        const TestRunCompleted(
          jobId: 'job_2',
          projectId: 'prj_1',
          branch: 'feat/x',
          baseline: false,
          failures: 29,
          newFailures: 3,
        ),
      ]);
    });
  });

  group('a run that cannot be trusted', () {
    test('fails when the SDK cannot be resolved', () async {
      final outcome = await step.run(
        input(flutterVersion: null),
        printing('baseline_27_failures.jsonl'),
      );

      expect(
        (outcome as StepFailed).message,
        contains('does not pin a Flutter version'),
      );
    });

    test('fails when the job is unknown', () async {
      final outcome = await step.run(
        input(),
        printing('baseline_27_failures.jsonl', jobId: 'job_nope'),
      );

      expect((outcome as StepFailed).message, 'There is no job job_nope.');
    });

    test('fails when it is cancelled', () async {
      final outcome = await step.run(
        input(),
        StreamingContext.single(
          const [],
          exit: const ProcessExit(exitCode: -15, cancelled: true),
        ),
      );

      expect((outcome as StepFailed).message, 'The tests were cancelled.');
      expect(await runs.forJob('job_1'), isNull);
    });

    test('fails when the output has no JSON', () async {
      final outcome = await step.run(
        input(),
        StreamingContext.single(const [
          'Resolving dependencies...',
          'Because x depends on y...',
        ], exit: const ProcessExit(exitCode: 65)),
      );

      expect(
        (outcome as StepFailed).message,
        'flutter test printed no machine output (exit code 65). The step log '
        'has what it printed.',
      );
    });

    test('fails when the run stops before it is over', () async {
      final lines = fixtureLines('baseline_27_failures.jsonl')
          .where((line) => !line.contains('"type":"done"'))
          .take(40)
          .toList();

      final outcome = await step.run(
        input(),
        StreamingContext.single(lines, exit: const ProcessExit(exitCode: -9)),
      );

      expect(
        (outcome as StepFailed).message,
        'flutter test stopped before the run was over (exit code -9), so its '
        'results cannot be trusted. The step log has its output.',
      );
      expect(await runs.forJob('job_1'), isNull);
    });

    test('fails when no test ran', () async {
      final outcome = await step.run(
        input(),
        StreamingContext.single(const [
          '{"protocolVersion":"0.1.1","type":"start","time":0}',
          '{"success":true,"type":"done","time":9}',
        ]),
      );

      expect((outcome as StepFailed).message, contains('ran no tests'));
      expect(await runs.forJob('job_1'), isNull);
    });
  });
}

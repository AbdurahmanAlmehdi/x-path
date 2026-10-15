import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_desktop/tests/tests.dart';
import 'package:xp_repositories/xp_repositories.dart';

import '../helpers/engine_fixtures.dart';
import '../helpers/fakes.dart';

const _devEnded = TestRunCompleted(
  jobId: 'job_dev',
  projectId: 'prj_1',
  branch: 'dev',
  baseline: false,
  failures: 2,
  newFailures: 1,
);

void main() {
  late MockTestsRepository tests;
  late MockJobsRepository jobs;
  late StreamController<Snapshot<List<TestBaseline>>> baselines;
  late StreamController<TestRunCompleted> completed;

  setUp(() {
    tests = MockTestsRepository();
    jobs = MockJobsRepository();
    baselines = StreamController();
    completed = StreamController();
    when(() => tests.watchBaselines('prj_1'))
        .thenAnswer((_) => baselines.stream);
    when(() => tests.completedRuns('prj_1'))
        .thenAnswer((_) => completed.stream);
    when(() => tests.watchRun('job_base'))
        .thenAnswer((_) => Stream.value(Snapshot(baselineRun, cached: true)));
    when(() => tests.watchRun('job_dev'))
        .thenAnswer((_) => Stream.value(Snapshot(devRun)));
    when(() => jobs.watchJob('job_dev'))
        .thenAnswer((_) => Stream.value(Snapshot(devJob)));
    when(() => jobs.watchJob('job_base')).thenAnswer(
      (_) => Stream.error(const ApiException('Gone.', statusCode: 404)),
    );
  });

  tearDown(() {
    unawaited(baselines.close());
    unawaited(completed.close());
  });

  test('events compare by value', () {
    expect(const TestsSubscriptionRequested('p', jobId: 'j').props, ['p', 'j']);
    expect(const TestsRunSelected('j').props, ['j']);
  });

  group('TestsState', () {
    test('shows the run picked, else the latest ended, else a baseline', () {
      expect(const TestsState().shownJobId, isNull);
      expect(
        TestsState(baselines: [releaseBaseline, mainBaseline]).shownJobId,
        'job_base',
      );
      expect(
        TestsState(
          baselines: [mainBaseline],
          completed: const [_devEnded],
        ).shownJobId,
        'job_dev',
      );
      expect(
        const TestsState(
          completed: [_devEnded],
          selectedJobId: 'job_x',
        ).shownJobId,
        'job_x',
      );
    });

    test('lists the runs it knows, the shown one as read', () {
      final state = TestsState(
        baselines: [releaseBaseline, mainBaseline],
        completed: const [_devEnded],
        selectedJobId: 'job_x',
        run: devRun,
        read: {'job_dev': devRun.run},
      );
      expect(state.runs, [
        KnownTestRun(
          jobId: 'job_dev',
          branch: 'dev',
          appPath: '.',
          createdAt: devRun.run.createdAt,
        ),
        const KnownTestRun(jobId: 'job_x'),
        KnownTestRun(
          jobId: 'job_base',
          branch: 'main',
          appPath: '.',
          createdAt: mainBaseline.createdAt,
          baseline: true,
        ),
        KnownTestRun(
          jobId: 'job_rel',
          branch: 'release/5.4.1',
          appPath: 'apps/captain',
          createdAt: releaseBaseline.createdAt,
          baseline: true,
        ),
      ]);
      expect(state.comparedBaseline, mainBaseline);
      expect(const TestsState().comparedBaseline, isNull);
    });

    test('reads the duration of the test step once it ended', () {
      expect(const TestsState().duration, isNull);
      expect(
        TestsState(job: devJob).duration,
        const Duration(minutes: 2, seconds: 41),
      );
      final running = Job(
        id: 'job_dev',
        projectId: 'prj_1',
        workflowVersionId: 'wfv_1',
        state: JobState.running,
        createdAt: devJob.createdAt,
        steps: [
          JobStep(
            ordinal: 0,
            kind: 'test',
            state: StepState.running,
            sideEffect: false,
            attempts: 1,
            startedAt: devJob.createdAt,
          ),
        ],
      );
      expect(TestsState(job: running).duration, isNull);
    });
  });

  group('TestsBloc', () {
    TestsBloc build() => TestsBloc(tests: tests, jobs: jobs);

    test('shows the newest baseline, then the run that just ended', () async {
      final bloc = build()..add(const TestsSubscriptionRequested('prj_1'));
      await pumpEventQueue();
      baselines.add(Snapshot([releaseBaseline, mainBaseline]));
      await pumpEventQueue();
      expect(bloc.state.loaded, isTrue);
      expect(bloc.state.shownJobId, 'job_base');
      expect(bloc.state.run, baselineRun);
      expect(bloc.state.runCached, isTrue);
      expect(bloc.state.job, isNull);

      completed.add(_devEnded);
      await pumpEventQueue();
      completed.add(_devEnded);
      await pumpEventQueue();
      expect(bloc.state.completed, [_devEnded]);
      expect(bloc.state.run, devRun);
      expect(bloc.state.job, devJob);

      bloc.add(const TestsRunSelected('job_base'));
      await pumpEventQueue();
      expect(bloc.state.run, baselineRun);
      await bloc.close();
    });

    test('shows the run asked for and says why it cannot', () async {
      when(() => tests.watchRun('job_x')).thenAnswer(
        (_) => Stream.error(const ApiException('No tests.', statusCode: 404)),
      );
      when(() => jobs.watchJob('job_x'))
          .thenAnswer((_) => const Stream.empty());
      final bloc = build()
        ..add(const TestsSubscriptionRequested('prj_1', jobId: 'job_x'));
      await pumpEventQueue();
      baselines.addError(const ApiException('Locked.', statusCode: 500));
      await pumpEventQueue();
      expect(bloc.state.shownJobId, 'job_x');
      expect(bloc.state.runError, 'No tests.');
      expect(bloc.state.error, 'Locked.');
      expect(bloc.state.loaded, isTrue);
      await bloc.close();
    });
  });
}

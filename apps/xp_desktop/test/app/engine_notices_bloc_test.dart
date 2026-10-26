import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_desktop/app/bloc/engine_notices_bloc.dart';
import 'package:xp_repositories/xp_repositories.dart';

import '../helpers/fakes.dart';
import '../helpers/job_fixtures.dart';

class _MockNoticesRepository extends Mock implements NoticesRepository;

NotificationRaised _raised(
  NotificationKind kind, {
  String? projectId,
  String? releaseId,
  String? jobId,
}) => NotificationRaised(
  kind: kind,
  level: NotificationLevel.info,
  title: kind.wire,
  body: 'body',
  projectId: projectId,
  releaseId: releaseId,
  jobId: jobId,
);

/// A run whose job `job_q` waits for a runner, or runs when [waiting] is
/// false.
Run _run({bool waiting = true}) {
  final run = runningRun().run;
  return Run(
    id: 'run_1',
    projectId: 'prj_1',
    workflowId: run.workflowId,
    workflowVersionId: run.workflowVersionId,
    sha: run.sha,
    state: RunState.running,
    locksProject: false,
    createdAt: run.createdAt,
    jobs: [
      RunJob(
        id: 'job_q',
        name: 'Build prod for ios',
        stage: 1,
        state: waiting ? JobState.queued : JobState.running,
        message: waiting ? 'No connected runner can do ios-sign.' : null,
      ),
      const RunJob(
        id: 'job_r',
        name: 'Build prod for android',
        stage: 1,
        state: JobState.queued,
      ),
    ],
  );
}

void main() {
  late _MockNoticesRepository notices;
  late MockJobsRepository jobs;
  late StreamController<EngineEvent> events;
  late StreamController<Snapshot<List<Run>>> runs;
  late StreamController<void> ticks;
  late DateTime now;

  setUp(() {
    notices = _MockNoticesRepository();
    jobs = MockJobsRepository();
    events = StreamController<EngineEvent>();
    runs = StreamController<Snapshot<List<Run>>>();
    ticks = StreamController<void>();
    now = DateTime.utc(2026, 10, 25, 12);
    when(notices.watchNotices).thenAnswer((_) => events.stream);
    when(jobs.watchActiveRuns).thenAnswer((_) => runs.stream);
  });

  EngineNoticesBloc build() => EngineNoticesBloc(
    notices: notices,
    jobs: jobs,
    now: () => now,
    ticks: ticks.stream,
  );

  test('names the kinds of the engine it shows, and not approvals', () {
    expect([
      for (final kind in NotificationKind.values) ?NoticeKind.of(kind),
    ], NoticeKind.values.take(7));
  });

  test('each notice opens what it is about', () {
    expect(
      EngineRaisedNotice(
        NoticeKind.jobFailed,
        _raised(NotificationKind.jobFailed, jobId: 'job_1'),
      ).target,
      'job:job_1',
    );
    expect(
      EngineRaisedNotice(
        NoticeKind.releaseLive,
        _raised(
          NotificationKind.releaseLive,
          projectId: 'prj_1',
          releaseId: 'rel_1',
        ),
      ).target,
      'release:prj_1:rel_1',
    );
    expect(
      EngineRaisedNotice(
        NoticeKind.credentialExpired,
        _raised(NotificationKind.credentialExpired, projectId: 'prj_1'),
      ).target,
      'credentials:prj_1',
    );
    expect(
      EngineRaisedNotice(
        NoticeKind.secretsLocked,
        _raised(NotificationKind.secretsLocked),
      ).target,
      'settings',
    );
    const lost = RunnerLeaseLost(
      runnerId: 'rnr_1',
      jobId: 'job_1',
      projectId: 'prj_1',
      reason: 'lapsed',
      state: JobState.queued,
    );
    expect(const RunnerLostNotice(lost).target, 'job:job_1');
    expect(const RunnerLostNotice(lost).props, [lost]);
    const capability = CapabilityLostNotice(runner: 'mac', lost: ['ios-sign']);
    expect(capability.target, 'runners');
    expect(capability.kind, NoticeKind.capabilityLost);
    expect(capability.props, [
      'mac',
      ['ios-sign'],
    ]);
    final waiting = JobWaitingNotice(
      run: _run(),
      jobId: 'job_q',
      jobName: 'n',
      reason: 'r',
    );
    expect(waiting.target, 'run:run_1:prj_1:job_q');
    expect(waiting.kind, NoticeKind.jobWaiting);
    expect(waiting.props, hasLength(4));
  });

  test('ticks every minute on the clock by default', () async {
    final bloc = EngineNoticesBloc(notices: notices, jobs: jobs);

    expect(bloc.state, const EngineNoticesState());
    await bloc.close();
  });

  group('EngineNoticesBloc', () {
    blocTest<EngineNoticesBloc, EngineNoticesState>(
      'turns what the engine says into notices, once each',
      build: build,
      act: (bloc) async {
        bloc.add(const EngineNoticesStarted());
        await Future<void>.delayed(Duration.zero);
        events
          ..add(_raised(NotificationKind.jobFailed, jobId: 'job_1'))
          ..add(_raised(NotificationKind.approvalRequested))
          ..add(
            const RunnerLeaseLost(
              runnerId: 'rnr_1',
              jobId: 'job_2',
              projectId: 'prj_1',
              reason: 'lapsed',
              state: JobState.queued,
            ),
          )
          ..add(
            const RunnerLeaseLost(
              runnerId: 'rnr_1',
              jobId: 'job_3',
              projectId: 'prj_1',
              reason: 'revoked',
              state: JobState.queued,
            ),
          )
          ..add(
            const RunnerCapabilitiesChanged(
              runnerId: 'rnr_1',
              name: 'mac',
              from: ['flutter'],
              to: ['flutter', 'ios-sign'],
            ),
          )
          ..add(
            const RunnerCapabilitiesChanged(
              runnerId: 'rnr_1',
              name: 'mac',
              from: ['flutter', 'ios-sign'],
              to: ['flutter'],
            ),
          )
          ..add(const ProjectEdited(projectId: 'prj_1'));
      },
      expect: () => [
        isA<EngineNoticesState>()
            .having((s) => s.count, 'count', 1)
            .having((s) => s.notice?.kind, 'kind', NoticeKind.jobFailed),
        isA<EngineNoticesState>()
            .having((s) => s.count, 'count', 2)
            .having((s) => s.notice?.kind, 'kind', NoticeKind.runnerLost),
        isA<EngineNoticesState>()
            .having((s) => s.count, 'count', 3)
            .having(
              (s) => s.notice,
              'notice',
              const CapabilityLostNotice(runner: 'mac', lost: ['ios-sign']),
            ),
      ],
    );

    blocTest<EngineNoticesBloc, EngineNoticesState>(
      'tells once when a job has waited ten minutes for a runner',
      build: build,
      act: (bloc) async {
        bloc.add(const EngineNoticesStarted());
        await Future<void>.delayed(Duration.zero);
        runs.add(Snapshot([_run()]));
        await Future<void>.delayed(Duration.zero);
        now = now.add(const Duration(minutes: 9));
        ticks.add(null);
        await Future<void>.delayed(Duration.zero);
        now = now.add(const Duration(minutes: 1));
        ticks.add(null);
        await Future<void>.delayed(Duration.zero);
        ticks.add(null);
        runs
          ..add(Snapshot([_run(waiting: false)]))
          ..addError(const ConnectionException('away'));
      },
      expect: () => [
        EngineNoticesState(running: [_run()]),
        EngineNoticesState(
          running: [_run()],
          notice: JobWaitingNotice(
            run: _run(),
            jobId: 'job_q',
            jobName: 'Build prod for ios',
            reason: 'No connected runner can do ios-sign.',
          ),
          count: 1,
        ),
        isA<EngineNoticesState>().having((s) => s.running, 'running', [
          _run(waiting: false),
        ]),
      ],
    );

    blocTest<EngineNoticesBloc, EngineNoticesState>(
      'tells the same notice twice when it comes twice',
      build: build,
      act: (bloc) async {
        bloc.add(const EngineNoticesStarted());
        await Future<void>.delayed(Duration.zero);
        events
          ..add(_raised(NotificationKind.jobFailed, jobId: 'job_1'))
          ..add(_raised(NotificationKind.jobFailed, jobId: 'job_1'));
      },
      expect: () => [
        isA<EngineNoticesState>().having((s) => s.count, 'count', 1),
        isA<EngineNoticesState>().having((s) => s.count, 'count', 2),
      ],
    );

    blocTest<EngineNoticesBloc, EngineNoticesState>(
      'forgets a job that stopped waiting before the limit',
      build: build,
      act: (bloc) async {
        bloc.add(const EngineNoticesStarted());
        await Future<void>.delayed(Duration.zero);
        runs.add(Snapshot([_run()]));
        await Future<void>.delayed(Duration.zero);
        runs.add(Snapshot([_run(waiting: false)]));
        await Future<void>.delayed(Duration.zero);
        now = now.add(const Duration(minutes: 5));
        runs.add(Snapshot([_run()]));
        await Future<void>.delayed(Duration.zero);
        now = now.add(const Duration(minutes: 9));
        ticks.add(null);
      },
      verify: (bloc) => expect(bloc.state.count, 0),
    );
  });
}

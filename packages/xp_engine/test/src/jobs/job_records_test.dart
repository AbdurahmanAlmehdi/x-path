import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  final at = DateTime.utc(2026, 10, 13, 9);

  group('JobRecord', () {
    final job = JobRecord(
      id: 'job_1',
      workflowVersionId: 'wfv_1',
      projectId: 'prj_1',
      releaseId: 'rel_1',
      sha: 'abc',
      state: JobState.failed,
      runnerId: 'run_1',
      message: 'boom',
      createdAt: at,
      startedAt: at,
      finishedAt: at,
    );

    test('keeps everything when copied without changes', () {
      expect(job.copyWith(), job);
    });

    test('replaces the state', () {
      expect(job.copyWith(state: JobState.running).state, JobState.running);
    });

    test('clears the message and the times when told to', () {
      final cleared = job.copyWith(
        message: null,
        startedAt: null,
        finishedAt: null,
      );

      expect(cleared.message, isNull);
      expect(cleared.startedAt, isNull);
      expect(cleared.finishedAt, isNull);
      expect(cleared.releaseId, 'rel_1');
    });

    test('replaces and clears the runner and its lease', () {
      final leased = job.copyWith(
        runnerId: 'rnr_1',
        leaseUntil: at.add(const Duration(seconds: 90)),
      );

      expect(leased.runnerId, 'rnr_1');
      expect(leased.leaseUntil, at.add(const Duration(seconds: 90)));
      expect(leased.copyWith().leaseUntil, leased.leaseUntil);
      expect(leased == job, isFalse);
      final cleared = leased.copyWith(runnerId: null, leaseUntil: null);
      expect(cleared.runnerId, isNull);
      expect(cleared.leaseUntil, isNull);
    });

    test('replaces the message and the times', () {
      final later = at.add(const Duration(hours: 1));
      final changed = job.copyWith(
        message: 'new',
        startedAt: later,
        finishedAt: later,
      );

      expect(changed.message, 'new');
      expect(changed.startedAt, later);
      expect(changed.finishedAt, later);
    });
  });

  group('StepRecord', () {
    final step = StepRecord(
      jobId: 'job_1',
      ordinal: 2,
      kind: 'command',
      sideEffect: true,
      input: const {'executable': 'ls'},
      state: StepState.failed,
      attempts: 2,
      result: const {'a': 1},
      message: 'boom',
      pgid: 123,
      logPath: '/logs/x.log',
      startedAt: at,
      finishedAt: at,
    );

    test('starts pending without attempts', () {
      const fresh = StepRecord(
        jobId: 'j',
        ordinal: 0,
        kind: 'k',
        sideEffect: false,
        input: {},
      );

      expect(fresh.state, StepState.pending);
      expect(fresh.attempts, 0);
    });

    test('keeps everything when copied without changes', () {
      expect(step.copyWith(), step);
    });

    test('replaces state and attempts', () {
      final changed = step.copyWith(state: StepState.running, attempts: 3);

      expect(changed.state, StepState.running);
      expect(changed.attempts, 3);
    });

    test('clears what can be cleared', () {
      final cleared = step.copyWith(
        result: null,
        message: null,
        pgid: null,
        logPath: null,
        startedAt: null,
        finishedAt: null,
      );

      expect(cleared.result, isNull);
      expect(cleared.message, isNull);
      expect(cleared.pgid, isNull);
      expect(cleared.logPath, isNull);
      expect(cleared.startedAt, isNull);
      expect(cleared.finishedAt, isNull);
      expect(cleared.input, step.input);
    });

    test('replaces what can be replaced', () {
      final later = at.add(const Duration(hours: 1));
      final changed = step.copyWith(
        result: const {'b': 2},
        message: 'new',
        pgid: 9,
        logPath: '/y.log',
        startedAt: later,
        finishedAt: later,
      );

      expect(changed.result, {'b': 2});
      expect(changed.message, 'new');
      expect(changed.pgid, 9);
      expect(changed.logPath, '/y.log');
      expect(changed.startedAt, later);
      expect(changed.finishedAt, later);
    });

    test('shows its API form without internals', () {
      expect(
        step.toJobStep(),
        JobStep(
          ordinal: 2,
          kind: 'command',
          state: StepState.failed,
          sideEffect: true,
          attempts: 2,
          result: const {'a': 1},
          message: 'boom',
          startedAt: at,
          finishedAt: at,
        ),
      );
    });
  });

  test('toJob joins a job and its steps', () {
    final job = toJob(
      JobRecord(
        id: 'job_1',
        workflowVersionId: 'wfv_1',
        projectId: 'prj_1',
        state: JobState.queued,
        createdAt: at,
      ),
      const [
        StepRecord(
          jobId: 'job_1',
          ordinal: 0,
          kind: 'command',
          sideEffect: false,
          input: {},
        ),
      ],
    );

    expect(job.id, 'job_1');
    expect(job.state, JobState.queued);
    expect(job.steps.single.kind, 'command');
  });
}

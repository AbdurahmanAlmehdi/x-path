import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/job_harness.dart';

void main() {
  late ManualClock clock;
  late InMemoryJobRepository jobs;
  late FakeProcessGroupControl control;
  late InMemorySecretFileStore secretFiles;
  late InMemoryEventLog events;
  late JobRecovery recovery;

  Future<void> addJob(
    String id,
    List<StepRecord> steps, {
    JobState state = JobState.running,
  }) => jobs.create(
    JobRecord(
      id: id,
      workflowVersionId: 'wfv_1',
      projectId: 'prj_1',
      state: state,
      createdAt: clock.now(),
    ),
    steps,
  );

  StepRecord step(
    String jobId,
    int ordinal, {
    StepState state = StepState.pending,
    bool sideEffect = false,
    int? pgid,
  }) => StepRecord(
    jobId: jobId,
    ordinal: ordinal,
    kind: 'command',
    sideEffect: sideEffect,
    input: const {},
    state: state,
    attempts: state == StepState.pending ? 0 : 1,
    pgid: pgid,
  );

  setUp(() {
    clock = ManualClock(DateTime.utc(2026, 10, 13, 9));
    jobs = InMemoryJobRepository();
    control = FakeProcessGroupControl(alive: [501, 502, 503]);
    secretFiles = InMemorySecretFileStore();
    events = InMemoryEventLog(clock: clock);
    recovery = JobRecovery(
      jobs: jobs,
      killer: ProcessGroupKiller(
        control: control,
        grace: const Duration(seconds: 1),
        pollInterval: const Duration(milliseconds: 100),
        delay: (_) async {},
      ),
      secretFiles: secretFiles,
      events: events,
      clock: clock,
    );
  });

  test('a job that ran on a remote runner holds no lease any more', () async {
    await jobs.create(
      JobRecord(
        id: 'job_r',
        workflowVersionId: 'wfv_1',
        projectId: 'prj_1',
        state: JobState.running,
        runnerId: 'rnr_1',
        leaseUntil: clock.now().add(const Duration(seconds: 60)),
        createdAt: clock.now(),
      ),
      [step('job_r', 0, state: StepState.running)],
    );

    final report = await recovery.recover();

    expect(report.resumable, ['job_r']);
    final job = (await jobs.get('job_r'))!;
    expect(job.state, JobState.interrupted);
    expect(job.runnerId, isNull);
    expect(job.leaseUntil, isNull);
    expect(control.signals, isEmpty);
  });

  test('does nothing when no job was running', () async {
    await addJob('job_q', [step('job_q', 0)], state: JobState.queued);
    await addJob('job_f', [step('job_f', 0)], state: JobState.failed);

    final report = await recovery.recover();

    expect(report.resumable, isEmpty);
    expect(report.waiting, isEmpty);
    expect(control.signals, isEmpty);
    expect((await jobs.get('job_q'))!.state, JobState.queued);
  });

  test(
    'stops the process group of the running step and interrupts it',
    () async {
      await addJob('job_1', [
        step('job_1', 0, state: StepState.succeeded),
        step('job_1', 1, state: StepState.running, pgid: 501),
        step('job_1', 2),
      ]);

      final report = await recovery.recover();

      expect(control.signals, ['TERM 501']);
      expect(report.resumable, ['job_1']);
      expect(report.waiting, isEmpty);
      final job = (await jobs.get('job_1'))!;
      expect(job.state, JobState.interrupted);
      expect(job.message, 'The engine stopped while the job was running.');
      expect(job.finishedAt, clock.now());
      final steps = await jobs.steps('job_1');
      expect(steps.map((s) => s.state), [
        StepState.succeeded,
        StepState.interrupted,
        StepState.pending,
      ]);
      expect(steps[1].pgid, isNull);
      expect(steps[1].message, contains('engine stopped'));
    },
  );

  test('kills a group that ignores SIGTERM', () async {
    control.dieOnTerminate = false;
    await addJob('job_1', [
      step('job_1', 0, state: StepState.running, pgid: 501),
    ]);

    await recovery.recover();

    expect(control.signals, ['TERM 501', 'KILL 501']);
  });

  test(
    'makes a job with an interrupted side-effect step wait for a resume',
    () async {
      await addJob('job_1', [
        step('job_1', 0, state: StepState.running, sideEffect: true, pgid: 502),
      ]);
      await addJob('job_2', [
        step('job_2', 0, state: StepState.running, pgid: 503),
      ]);

      final report = await recovery.recover();

      expect(report.waiting, ['job_1']);
      expect(report.resumable, ['job_2']);
      expect((await jobs.get('job_1'))!.state, JobState.waitingForResume);
      expect((await jobs.get('job_2'))!.state, JobState.interrupted);
    },
  );

  test('copes with a step that has no process group yet', () async {
    await addJob('job_1', [step('job_1', 0, state: StepState.running)]);

    final report = await recovery.recover();

    expect(control.signals, isEmpty);
    expect(report.resumable, ['job_1']);
  });

  test('copes with a group that is gone', () async {
    await addJob('job_1', [
      step('job_1', 0, state: StepState.running, pgid: 999),
    ]);

    await recovery.recover();

    expect(control.signals, isEmpty);
    expect((await jobs.get('job_1'))!.state, JobState.interrupted);
  });

  test('interrupts a job that was between two steps', () async {
    await addJob('job_1', [
      step('job_1', 0, state: StepState.succeeded),
      step('job_1', 1),
    ]);

    final report = await recovery.recover();

    expect(report.resumable, ['job_1']);
    expect((await jobs.steps('job_1')).map((s) => s.state), [
      StepState.succeeded,
      StepState.pending,
    ]);
  });

  test('deletes the secret files of the jobs it recovers', () async {
    await addJob('job_1', [step('job_1', 0, state: StepState.running)]);
    await addJob('job_2', [step('job_2', 0)], state: JobState.queued);

    await recovery.recover();

    expect(secretFiles.deleted, ['job_1']);
  });

  test('announces the interrupted step and the new state of the job', () async {
    await addJob('job_1', [
      step('job_1', 0, state: StepState.running, sideEffect: true, pgid: 501),
    ]);
    final logged = <SequencedEvent>[];
    final subscription = events.subscribe().listen(logged.add);

    await recovery.recover();
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();

    expect(logged.map((e) => e.event), [
      const JobStepChanged(
        jobId: 'job_1',
        ordinal: 0,
        kind: 'command',
        state: StepState.interrupted,
      ),
      const JobStateChanged(
        jobId: 'job_1',
        projectId: 'prj_1',
        state: JobState.waitingForResume,
      ),
    ]);
  });

  test('a recovered job resumes: a step without side effects runs again, '
      'one with side effects only on an explicit resume', () async {
    final harness = JobHarness.create(repository: jobs);
    final plain = await harness.create([harness.command('build')]);
    final risky = await harness.create([
      harness.command('upload', sideEffect: true),
    ]);
    for (final id in [plain.id, risky.id]) {
      await jobs.updateJob(
        (await jobs.get(id))!.copyWith(state: JobState.running),
      );
      await jobs.updateStep(
        (await jobs.steps(id)).single.copyWith(state: StepState.running),
      );
    }

    final report = await JobRecovery(
      jobs: jobs,
      killer: ProcessGroupKiller(control: control),
      secretFiles: secretFiles,
      events: events,
      clock: clock,
    ).recover();

    expect(report.resumable, [plain.id]);
    expect(report.waiting, [risky.id]);
    // Nothing ran by itself.
    expect(harness.supervisor.specs, isEmpty);
    expect(
      (await harness.runner.get(risky.id)).state,
      JobState.waitingForResume,
    );

    // The owner resumes the one that waited; it asks first, then runs.
    await harness.runner.resume(risky.id);
    final job = await harness.runner.whenFinished(risky.id);

    expect(job.state, JobState.succeeded);
    expect(harness.supervisor.specs.map((s) => s.executable), ['upload']);

    await harness.runner.resume(plain.id);
    expect(
      (await harness.runner.whenFinished(plain.id)).state,
      JobState.succeeded,
    );
  });
}

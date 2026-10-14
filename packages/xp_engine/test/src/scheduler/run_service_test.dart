import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/job_harness.dart';

void main() {
  late JobHarness harness;
  late InMemoryRunRepository runs;
  late RunService service;

  setUp(() async {
    harness = JobHarness.create();
    runs = InMemoryRunRepository();
    service = RunService(
      runs: runs,
      jobs: harness.jobs,
      control: harness.runner,
    );
    await runs.create(
      RunRecord(
        id: 'run_1',
        projectId: 'prj_1',
        workflowId: 'wf_1',
        workflowVersionId: 'wfv_1',
        sha: 'a' * 40,
        locksProject: false,
        createdAt: DateTime.utc(2026),
      ),
    );
  });

  Future<Job> job(String name, {int stage = 0}) => harness.runner.create(
    workflowVersionId: 'wfv_1',
    projectId: 'prj_1',
    runId: 'run_1',
    stage: stage,
    name: name,
    steps: [harness.script()],
  );

  test('shows a run with its jobs', () async {
    await job('prepare');
    await job('build', stage: 1);

    final run = await service.get('run_1');

    expect(run.state, RunState.queued);
    expect(run.jobs.map((j) => (j.name, j.stage, j.state)), [
      ('prepare', 0, JobState.queued),
      ('build', 1, JobState.queued),
    ]);
  });

  test('says when there is no such run', () async {
    await expectLater(
      service.get('run_nope'),
      throwsA(
        isA<RunNotFoundException>()
            .having((e) => e.id, 'id', 'run_nope')
            .having((e) => e.message, 'message', 'There is no run run_nope.'),
      ),
    );
    await expectLater(
      service.cancel('run_nope'),
      throwsA(isA<RunNotFoundException>()),
    );
  });

  test('cancels the jobs that have not ended, and leaves the others', () async {
    final done = await job('done');
    await harness.runner.start(done.id);
    await harness.runner.whenFinished(done.id);
    final queued = await job('queued');
    final later = await job('later', stage: 1);

    final run = await service.cancel('run_1');

    expect(run.state, RunState.cancelled);
    expect(
      {for (final j in run.jobs) j.name: j.state},
      {
        'done': JobState.succeeded,
        'queued': JobState.cancelled,
        'later': JobState.cancelled,
      },
    );
    expect((await harness.runner.get(queued.id)).state, JobState.cancelled);
    expect((await harness.runner.get(later.id)).state, JobState.cancelled);
  });

  test('refuses to cancel a run that ended', () async {
    final done = await job('done');
    await harness.runner.start(done.id);
    await harness.runner.whenFinished(done.id);

    await expectLater(
      service.cancel('run_1'),
      throwsA(
        isA<RunStateException>().having(
          (e) => e.message,
          'message',
          'Run run_1 has ended: every job of it has.',
        ),
      ),
    );
  });

  test('the exceptions print their messages', () {
    expect(const RunException('m').toString(), 'RunException: m');
    expect(
      const RunNotFoundException('r').toString(),
      'RunNotFoundException: There is no run r.',
    );
    expect(const RunStateException('m').toString(), 'RunStateException: m');
  });
}

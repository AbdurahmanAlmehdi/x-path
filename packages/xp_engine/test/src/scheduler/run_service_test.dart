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

  group('rerunFailed', () {
    test('resumes a failed job at the step that failed, and keeps what the '
        'jobs before made', () async {
      final ran = <String>[];
      var sendFails = true;
      final flaky = JobHarness.create(
        scripted: ScriptedStep(
          onRun: (input, context) async {
            final name = input['name'] as String;
            ran.add(name);
            if (name == 'send' && sendFails) {
              sendFails = false;
              return const StepFailed('the store was down');
            }
            return StepSucceeded({'made': '$name.out'});
          },
        ),
      );
      final again = RunService(
        runs: runs,
        jobs: flaky.jobs,
        control: flaky.runner,
      );
      StepPlan step(String name) => flaky.script(input: {'name': name});
      final build = await flaky.runner.create(
        workflowVersionId: 'wfv_1',
        projectId: 'prj_1',
        runId: 'run_1',
        name: 'build',
        steps: [step('compile')],
      );
      final upload = await flaky.runner.create(
        workflowVersionId: 'wfv_1',
        projectId: 'prj_1',
        runId: 'run_1',
        stage: 1,
        name: 'upload',
        steps: [step('prepare'), step('send')],
      );
      await flaky.runner.start(build.id);
      await flaky.runner.whenFinished(build.id);
      await flaky.runner.start(upload.id);
      await flaky.runner.whenFinished(upload.id);
      expect((await again.get('run_1')).state, RunState.failed);
      expect(ran, ['compile', 'prepare', 'send']);

      await again.rerunFailed('run_1');
      await flaky.runner.whenFinished(upload.id);

      expect((await again.get('run_1')).state, RunState.succeeded);
      expect(ran, [
        'compile',
        'prepare',
        'send',
        'send',
      ], reason: 'the upload resumed at send; the build and prepare ran once');
      final built = (await flaky.jobs.steps(build.id)).single;
      expect(built.attempts, 1);
      expect(built.result, {
        'made': 'compile.out',
      }, reason: 'kept, not rebuilt');
      final prepared = (await flaky.jobs.steps(upload.id)).first;
      expect(prepared.attempts, 1);
      expect(prepared.result, {'made': 'prepare.out'});
    });

    test('refuses a run without a failed job, and no run', () async {
      final done = await job('done');
      await harness.runner.start(done.id);
      await harness.runner.whenFinished(done.id);

      await expectLater(
        service.rerunFailed('run_1'),
        throwsA(
          isA<RunStateException>().having(
            (e) => e.message,
            'message',
            'Run run_1 has no failed job to run again.',
          ),
        ),
      );
      await expectLater(
        service.rerunFailed('run_nope'),
        throwsA(isA<RunNotFoundException>()),
      );
    });
  });

  test('the exceptions print their messages', () {
    expect(const RunException('m').toString(), 'RunException: m');
    expect(
      const RunNotFoundException('r').toString(),
      'RunNotFoundException: There is no run r.',
    );
    expect(const RunStateException('m').toString(), 'RunStateException: m');
  });

  group('list', () {
    setUp(() async {
      for (final (id, project, minutes) in [
        ('run_2', 'prj_1', 2),
        ('run_3', 'prj_2', 3),
        ('run_4', 'prj_1', 4),
      ]) {
        await runs.create(
          RunRecord(
            id: id,
            projectId: project,
            workflowId: 'wf_1',
            workflowVersionId: 'wfv_1',
            sha: 'a' * 40,
            locksProject: false,
            createdAt: DateTime.utc(2026).add(Duration(minutes: minutes)),
            request: const {
              'flavors': ['dev'],
              'inputs': <String, Object?>{},
            },
          ),
        );
      }
    });

    test(
      'gives the runs newest first, with where the next page starts',
      () async {
        final first = await service.list(limit: 2);
        expect(first.runs.map((r) => r.id), ['run_4', 'run_3']);
        expect(first.next, 'run_3');
        expect(first.runs.first.request?.flavors, ['dev']);

        final second = await service.list(limit: 2, before: first.next);
        expect(second.runs.map((r) => r.id), ['run_2', 'run_1']);
        expect(second.next, 'run_1');
        expect(second.runs.last.request, isNull, reason: 'none stored');

        final last = await service.list(limit: 2, before: second.next);
        expect(last.runs, isEmpty);
        expect(last.next, isNull);
      },
    );

    test('filters by project, workflow and state', () async {
      expect((await service.list(projectId: 'prj_1')).runs.map((r) => r.id), [
        'run_4',
        'run_2',
        'run_1',
      ]);
      expect((await service.list(workflowId: 'wf_x')).runs, isEmpty);

      await job('prepare');
      final queued = await service.list(state: RunState.queued, limit: 1);
      expect(queued.runs.single.id, 'run_1');
      expect(queued.next, 'run_1');
      expect((await service.list(state: RunState.succeeded)).runs, isEmpty);
      expect(
        (await service.list(state: RunState.cancelled)).runs.map((r) => r.id),
        ['run_4', 'run_3', 'run_2'],
        reason: 'a run without jobs ran nothing',
      );
    });

    test('says when the run to page from is not there', () async {
      await expectLater(
        service.list(before: 'run_nope'),
        throwsA(isA<RunNotFoundException>()),
      );
    });

    test('reads a request it cannot read as none', () async {
      await runs.create(
        RunRecord(
          id: 'run_odd',
          projectId: 'prj_1',
          workflowId: 'wf_1',
          workflowVersionId: 'wfv_1',
          sha: 'a' * 40,
          locksProject: false,
          createdAt: DateTime.utc(2027),
          request: const {'flavors': 'dev'},
        ),
      );

      expect((await service.get('run_odd')).request, isNull);
    });
  });
}

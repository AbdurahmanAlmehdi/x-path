import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/job_harness.dart';

void main() {
  late ScriptedStep gate;
  late JobHarness harness;
  var open = false;
  var reason = 'Waiting for the owner.';

  setUp(() {
    open = false;
    reason = 'Waiting for the owner.';
    gate = ScriptedStep(
      kind: 'gate',
      onRun: (input, context) =>
          Future<StepOutcome<Map<String, dynamic>>>.value(
            open ? const StepSucceeded({'ran': true}) : StepWaiting(reason),
          ),
    );
    harness = JobHarness.create(scripted: gate);
  });

  StepPlan waitingStep() => StepPlan.of(gate, {'sideEffect': false});

  test('a step that waits stops the job in waiting_for_approval', () async {
    final job = await harness.run([waitingStep(), harness.command('after')]);

    expect(job.state, JobState.waitingForApproval);
    expect(job.message, 'Step 0 (gate) waits: Waiting for the owner.');
    expect(job.finishedAt, isNotNull);
    expect(job.steps.map((s) => s.state), [
      StepState.waitingForApproval,
      StepState.pending,
    ]);
    expect(job.steps.first.message, 'Waiting for the owner.');
    expect(harness.supervisor.specs, isEmpty);
    expect(await harness.jobEvents(), [
      'job queued',
      'job running',
      'step 0 running',
      'step 0 waitingForApproval',
      'job waiting_for_approval',
    ]);
  });

  test('is resumed, and goes on once the step lets it', () async {
    final waiting = await harness.run([
      waitingStep(),
      harness.command('after'),
    ]);

    open = true;
    await harness.runner.resume(waiting.id);
    final done = await harness.runner.whenFinished(waiting.id);

    expect(done.state, JobState.succeeded);
    expect(done.steps.first.attempts, 2);
    expect(done.message, isNull);
  });

  test('is resumed, and waits again while nobody decided', () async {
    reason = 'Still waiting.';
    final waiting = await harness.run([waitingStep()]);

    await harness.runner.resume(waiting.id);
    final again = await harness.runner.whenFinished(waiting.id);

    expect(again.state, JobState.waitingForApproval);
    expect(again.steps.single.attempts, 2);
  });

  test('is cancelled at once, and its step with it', () async {
    final waiting = await harness.run([waitingStep()]);

    final cancelled = await harness.runner.cancel(waiting.id);

    expect(cancelled.state, JobState.cancelled);
    expect(cancelled.steps.single.state, StepState.cancelled);
  });

  test('cannot be resumed while it runs', () async {
    final waiting = await harness.run([waitingStep()]);
    await harness.runner.requeue(waiting.id);

    await expectLater(
      harness.runner.resume(waiting.id),
      throwsA(isA<JobStateException>()),
    );
  });

  group('requeue', () {
    test('puts a failed job back in the queue, ready to start', () async {
      harness.supervisor.handler = (process) => 3;
      final failed = await harness.run([harness.command('x')]);
      harness.supervisor.handler = (process) => 0;

      final queued = await harness.runner.requeue(failed.id);

      expect(queued.state, JobState.queued);
      expect(queued.message, isNull);
      expect(queued.finishedAt, isNull);
      await harness.runner.start(failed.id);
      expect(
        (await harness.runner.whenFinished(failed.id)).state,
        JobState.succeeded,
      );
    });

    test('can rewind to a step', () async {
      harness.supervisor.handler = (process) =>
          process.spec.executable == 'two' ? 1 : 0;
      final failed = await harness.run([
        harness.command('one'),
        harness.command('two'),
      ]);

      final queued = await harness.runner.requeue(failed.id, fromStep: 0);

      expect(queued.steps.map((s) => s.state), [
        StepState.pending,
        StepState.pending,
      ]);
    });

    test('refuses a job that cannot be resumed', () async {
      final done = await harness.run([harness.command('one')]);
      final queued = await harness.create([harness.command('two')]);

      await expectLater(
        harness.runner.requeue(done.id),
        throwsA(isA<JobStateException>()),
      );
      await expectLater(
        harness.runner.requeue(queued.id),
        throwsA(isA<JobStateException>()),
      );
      await expectLater(
        harness.runner.requeue('job_nope'),
        throwsA(isA<JobNotFoundException>()),
      );
    });
  });

  group('create', () {
    test('keeps the run, stage, name and capabilities', () async {
      final id = harness.runner.newJobId();

      final job = await harness.runner.create(
        id: id,
        workflowVersionId: 'wfv_1',
        projectId: 'prj_1',
        runId: 'run_1',
        stage: 2,
        name: 'build (ios)',
        capabilities: const ['flutter', 'ios-sign'],
        steps: const [],
      );

      expect(id, matches(RegExp(r'^job_[0-9a-f]{16}$')));
      expect(job.id, id);
      expect(job.runId, 'run_1');
      expect(job.stage, 2);
      expect(job.name, 'build (ios)');
      expect(job.capabilities, ['flutter', 'ios-sign']);
      final stored = (await harness.jobs.get(id))!;
      expect(stored.runId, 'run_1');
      expect(stored.stage, 2);
      expect((await harness.jobs.forRun('run_1')).map((j) => j.id), [id]);
    });

    test(
      'shows a job that was not dispatched without a run or stage',
      () async {
        final job = await harness.create(const []);

        expect(job.runId, isNull);
        expect(job.stage, isNull);
        expect(job.capabilities, isEmpty);
      },
    );
  });
}

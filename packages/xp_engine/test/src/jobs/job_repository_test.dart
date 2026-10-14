import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  late InMemoryJobRepository repository;
  final at = DateTime.utc(2026, 10, 13);

  JobRecord job(String id, [JobState state = JobState.queued]) => JobRecord(
    id: id,
    workflowVersionId: 'wfv_1',
    projectId: 'prj_1',
    state: state,
    createdAt: at,
  );

  StepRecord step(String jobId, int ordinal) => StepRecord(
    jobId: jobId,
    ordinal: ordinal,
    kind: 'command',
    sideEffect: false,
    input: const {},
  );

  setUp(() => repository = InMemoryJobRepository());

  test('stores a job with its steps', () async {
    await repository.create(job('a'), [step('a', 0), step('a', 1)]);

    expect(await repository.get('a'), job('a'));
    expect((await repository.steps('a')).map((s) => s.ordinal), [0, 1]);
    expect(await repository.get('b'), isNull);
    expect(await repository.steps('b'), isEmpty);
  });

  test('refuses a job twice', () async {
    await repository.create(job('a'), []);

    await expectLater(repository.create(job('a'), []), throwsStateError);
  });

  test('lists the jobs in the states asked for, oldest first', () async {
    await repository.create(job('a', JobState.running), []);
    await repository.create(job('b', JobState.failed), []);
    await repository.create(job('c', JobState.running), []);

    final running = await repository.list(states: {JobState.running});

    expect(running.map((j) => j.id), ['a', 'c']);
    expect(await repository.list(states: {JobState.queued}), isEmpty);
  });

  test('updates a job', () async {
    await repository.create(job('a'), []);

    await repository.updateJob(job('a', JobState.running));

    expect((await repository.get('a'))!.state, JobState.running);
  });

  test('cannot update a job it does not have', () async {
    await expectLater(repository.updateJob(job('x')), throwsStateError);
  });

  test('records the tool versions of a job, replacing earlier ones', () async {
    await repository.create(job('a'), const []);
    expect(await repository.tools('a'), isNull);

    await repository.saveTools('a', const JobTools(flutter: '3.47.5'));
    await repository.saveTools('a', const JobTools(flutter: '3.47.6'));

    expect(await repository.tools('a'), const JobTools(flutter: '3.47.6'));
    expect(await repository.tools('b'), isNull);
  });

  test('cannot record tools for a job it does not have', () async {
    await expectLater(
      repository.saveTools('x', const JobTools()),
      throwsStateError,
    );
  });

  test('updates a step', () async {
    await repository.create(job('a'), [step('a', 0)]);

    await repository.updateStep(step('a', 0).copyWith(attempts: 4));

    expect((await repository.steps('a')).single.attempts, 4);
  });

  test('cannot update a step it does not have', () async {
    await repository.create(job('a'), [step('a', 0)]);

    await expectLater(repository.updateStep(step('a', 1)), throwsStateError);
    await expectLater(repository.updateStep(step('x', 0)), throwsStateError);
  });

  test('hands out copies of the step list', () async {
    await repository.create(job('a'), [step('a', 0)]);

    (await repository.steps('a')).clear();

    expect(await repository.steps('a'), hasLength(1));
  });

  test('deletes a job with its steps and tools', () async {
    await repository.create(job('a'), [step('a', 0)]);
    await repository.saveTools('a', const JobTools(flutter: '3.47.6'));

    expect(await repository.delete('a'), isTrue);

    expect(await repository.get('a'), isNull);
    expect(await repository.steps('a'), isEmpty);
    expect(await repository.tools('a'), isNull);
    expect(await repository.delete('a'), isFalse);
  });
}

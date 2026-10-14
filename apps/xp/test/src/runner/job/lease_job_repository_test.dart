import 'package:test/test.dart';
import 'package:xp/src/runner/job/lease_job_repository.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  late List<StepRecord> reported;
  late List<(String, int, int?)> groups;
  late LeaseJobRepository repository;

  const step = StepRecord(
    jobId: 'job_1',
    ordinal: 0,
    kind: 'command',
    sideEffect: false,
    input: {},
  );

  setUp(() async {
    reported = [];
    groups = [];
    repository = LeaseJobRepository(
      onStep: reported.add,
      onProcessGroup: (jobId, ordinal, pgid) =>
          groups.add((jobId, ordinal, pgid)),
    );
    await repository.create(
      JobRecord(
        id: 'job_1',
        workflowVersionId: 'lease',
        projectId: 'prj_1',
        state: JobState.queued,
        createdAt: DateTime.utc(2026),
      ),
      [step],
    );
  });

  test('reports each new state of a step once', () async {
    await repository.updateStep(
      step.copyWith(state: StepState.running, attempts: 1),
    );
    await repository.updateStep(
      step.copyWith(state: StepState.running, attempts: 1, pgid: 4001),
    );
    await repository.updateStep(
      step.copyWith(state: StepState.succeeded, attempts: 1, pgid: null),
    );

    expect(reported.map((s) => (s.state, s.attempts)), [
      (StepState.running, 1),
      (StepState.succeeded, 1),
    ]);
  });

  test('reports a new attempt of the same state', () async {
    await repository.updateStep(
      step.copyWith(state: StepState.failed, attempts: 1),
    );
    await repository.updateStep(
      step.copyWith(state: StepState.failed, attempts: 2),
    );

    expect(reported.map((s) => s.attempts), [1, 2]);
  });

  test('does not report a step that was reset', () async {
    await repository.updateStep(step);

    expect(reported, isEmpty);
  });

  test('tells where the process of a step is, and when it is gone', () async {
    await repository.updateStep(
      step.copyWith(state: StepState.running, attempts: 1, pgid: 4001),
    );
    await repository.updateStep(
      step.copyWith(state: StepState.succeeded, attempts: 1, pgid: null),
    );

    expect(groups, [('job_1', 0, 4001), ('job_1', 0, null)]);
  });

  test('keeps the steps like any in-memory repository', () async {
    await repository.updateStep(
      step.copyWith(state: StepState.succeeded, attempts: 1),
    );

    expect((await repository.steps('job_1')).single.state, StepState.succeeded);
  });
}

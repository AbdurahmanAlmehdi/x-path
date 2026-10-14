import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

JobRecord _job(String id, {String? runId, int stage = 0}) => JobRecord(
  id: id,
  workflowVersionId: 'wfv_1',
  projectId: 'prj_1',
  state: JobState.queued,
  createdAt: DateTime.utc(2026),
  runId: runId,
  stage: stage,
  name: 'job $id',
  capabilities: const ['flutter'],
);

void main() {
  test(
    'the jobs of a run come by stage, then in the order they were made',
    () async {
      final repository = InMemoryJobRepository();
      for (final job in [
        _job('c', runId: 'run_1', stage: 1),
        _job('a', runId: 'run_1'),
        _job('x', runId: 'run_2'),
        _job('b', runId: 'run_1'),
        _job('plain'),
      ]) {
        await repository.create(job, const []);
      }

      expect((await repository.forRun('run_1')).map((job) => job.id), [
        'a',
        'b',
        'c',
      ]);
      expect(await repository.forRun('run_3'), isEmpty);
    },
  );

  test('a record keeps its run, stage, name and capabilities when updated', () {
    final job = _job('a', runId: 'run_1', stage: 2);

    final running = job.copyWith(state: JobState.running);

    expect(running.runId, 'run_1');
    expect(running.stage, 2);
    expect(running.name, 'job a');
    expect(running.capabilities, ['flutter']);
    expect(running, isNot(job));
    expect(job, _job('a', runId: 'run_1', stage: 2));
    expect(job, isNot(_job('a', runId: 'run_2', stage: 2)));
    expect(job, isNot(_job('a', runId: 'run_1', stage: 3)));
  });
}

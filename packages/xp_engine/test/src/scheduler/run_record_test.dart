import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

JobRecord _job(
  String id,
  JobState state, {
  int stage = 0,
  String? name,
  String? message,
}) => JobRecord(
  id: id,
  workflowVersionId: 'wfv_1',
  projectId: 'prj_1',
  state: state,
  createdAt: DateTime.utc(2026),
  runId: 'run_1',
  stage: stage,
  name: name,
  capabilities: const ['flutter'],
  message: message,
);

void main() {
  group('deriveRunState', () {
    test('is queued while nothing started', () {
      expect(
        deriveRunState([JobState.queued, JobState.queued]),
        RunState.queued,
      );
      expect(deriveRunState(const []), RunState.cancelled);
    });

    test(
      'is running while a job runs, is interrupted or waits for a resume',
      () {
        for (final state in [
          JobState.running,
          JobState.interrupted,
          JobState.waitingForResume,
        ]) {
          expect(
            deriveRunState([
              JobState.failed,
              state,
              JobState.waitingForApproval,
            ]),
            RunState.running,
            reason: state.wire,
          );
        }
      },
    );

    test('is waiting for approval when a gate waits and nothing runs', () {
      expect(
        deriveRunState([JobState.waitingForApproval, JobState.queued]),
        RunState.waitingForApproval,
      );
    });

    test('is failed or cancelled when a job is and none runs', () {
      expect(
        deriveRunState([JobState.succeeded, JobState.failed, JobState.queued]),
        RunState.failed,
      );
      expect(
        deriveRunState([JobState.cancelled, JobState.failed]),
        RunState.failed,
      );
      expect(
        deriveRunState([JobState.succeeded, JobState.cancelled]),
        RunState.cancelled,
      );
    });

    test('is succeeded when every job did', () {
      expect(
        deriveRunState([JobState.succeeded, JobState.succeeded]),
        RunState.succeeded,
      );
    });

    test('is running between two stages', () {
      expect(
        deriveRunState([JobState.succeeded, JobState.queued]),
        RunState.running,
      );
    });
  });

  group('RunRecord', () {
    final run = RunRecord(
      id: 'run_1',
      projectId: 'prj_1',
      workflowId: 'wf_1',
      workflowVersionId: 'wfv_1',
      sha: 'a' * 40,
      ref: 'main',
      locksProject: true,
      version: '1.2.3',
      build: 45,
      request: const {'ref': 'main'},
      createdAt: DateTime.utc(2026, 10, 13),
    );

    test('shows itself and its jobs to a client', () {
      final api = run.toRun([
        _job('job_1', JobState.succeeded, name: 'prepare'),
        _job('job_2', JobState.queued, stage: 1, message: 'Waiting.'),
      ]);

      expect(api.state, RunState.running);
      expect(api.locksProject, isTrue);
      expect(api.version, '1.2.3');
      expect(api.build, 45);
      expect(api.workflowId, 'wf_1');
      expect(api.jobs, const [
        RunJob(
          id: 'job_1',
          name: 'prepare',
          stage: 0,
          state: JobState.succeeded,
          capabilities: ['flutter'],
        ),
        RunJob(
          id: 'job_2',
          name: 'job_2',
          stage: 1,
          state: JobState.queued,
          capabilities: ['flutter'],
          message: 'Waiting.',
        ),
      ]);
    });

    test('holds the project or not, and compares by value', () {
      final held = run.withLockHeld(held: true);

      expect(run.lockHeld, isFalse);
      expect(held.lockHeld, isTrue);
      expect(held.id, run.id);
      expect(held.request, run.request);
      expect(held, isNot(run));
      expect(held.withLockHeld(held: false), run);
    });
  });

  group('InMemoryRunRepository', () {
    test('keeps runs, one per id, and who holds the lock', () async {
      final repository = InMemoryRunRepository();
      final first = RunRecord(
        id: 'run_1',
        projectId: 'prj_1',
        workflowId: 'wf_1',
        workflowVersionId: 'wfv_1',
        sha: 'a',
        locksProject: true,
        createdAt: DateTime.utc(2026),
      );
      await repository.create(first);
      await repository.create(
        RunRecord(
          id: 'run_2',
          projectId: 'prj_1',
          workflowId: 'wf_1',
          workflowVersionId: 'wfv_1',
          sha: 'a',
          locksProject: true,
          createdAt: DateTime.utc(2026),
        ),
      );

      expect(await repository.get('run_1'), first);
      expect(await repository.get('run_9'), isNull);
      expect(await repository.held(), isEmpty);
      await repository.setLockHeld('run_2', held: true);
      expect((await repository.held()).map((run) => run.id), ['run_2']);
      await repository.setLockHeld('run_2', held: false);
      expect(await repository.held(), isEmpty);
      await expectLater(repository.create(first), throwsStateError);
    });
  });
}

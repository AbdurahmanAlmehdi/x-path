import 'package:json_annotation/json_annotation.dart';
import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';

void main() {
  final created = DateTime.utc(2026, 10, 13, 9);

  group('JobState', () {
    test('uses snake_case on the wire', () {
      expect(JobState.waitingForResume.wire, 'waiting_for_resume');
      expect(JobState.running.wire, 'running');
    });

    test('is finished when it succeeded, failed or was cancelled', () {
      expect(JobState.values.where((state) => state.isFinished), [
        JobState.succeeded,
        JobState.failed,
        JobState.cancelled,
      ]);
    });
  });

  group('StepState', () {
    test('is done when it succeeded or was skipped', () {
      expect(StepState.values.where((state) => state.isDone), [
        StepState.succeeded,
        StepState.skipped,
      ]);
    });
  });

  group('JobStep', () {
    final step = JobStep(
      ordinal: 1,
      kind: 'command',
      state: StepState.succeeded,
      sideEffect: true,
      attempts: 2,
      result: const {'exitCode': 0},
      message: 'fine',
      startedAt: created,
      finishedAt: created.add(const Duration(seconds: 3)),
    );

    test('serializes every field', () {
      expect(step.toJson(), {
        'ordinal': 1,
        'kind': 'command',
        'state': 'succeeded',
        'sideEffect': true,
        'attempts': 2,
        'result': {'exitCode': 0},
        'message': 'fine',
        'startedAt': '2026-10-13T09:00:00.000Z',
        'finishedAt': '2026-10-13T09:00:03.000Z',
      });
    });

    test('leaves out what it does not have', () {
      const bare = JobStep(
        ordinal: 0,
        kind: 'command',
        state: StepState.pending,
        sideEffect: false,
        attempts: 0,
      );

      expect(bare.toJson().keys, [
        'ordinal',
        'kind',
        'state',
        'sideEffect',
        'attempts',
      ]);
    });

    test('round-trips through JSON', () {
      expect(JobStep.fromJson(step.toJson()), step);
    });
  });

  group('Job', () {
    final job = Job(
      id: 'job_1',
      projectId: 'prj_1',
      workflowVersionId: 'wfv_1',
      releaseId: 'rel_1',
      sha: 'a' * 40,
      state: JobState.waitingForResume,
      runnerId: 'run_1',
      message: 'engine stopped',
      createdAt: created,
      startedAt: created,
      finishedAt: created,
      steps: const [
        JobStep(
          ordinal: 0,
          kind: 'command',
          state: StepState.interrupted,
          sideEffect: true,
          attempts: 1,
        ),
      ],
    );

    test('serializes its state in snake_case and its steps inline', () {
      final json = job.toJson();

      expect(json['state'], 'waiting_for_resume');
      expect(json['createdAt'], '2026-10-13T09:00:00.000Z');
      expect((json['steps']! as List).single, isA<Map<String, dynamic>>());
    });

    test('round-trips through JSON', () {
      expect(Job.fromJson(job.toJson()), job);
    });

    test('leaves out what it does not have', () {
      final bare = Job(
        id: 'job_1',
        projectId: 'prj_1',
        workflowVersionId: 'wfv_1',
        state: JobState.queued,
        createdAt: created,
        steps: const [],
      );

      expect(bare.toJson().keys, [
        'id',
        'projectId',
        'workflowVersionId',
        'state',
        'createdAt',
        'steps',
      ]);
    });
  });

  group('ResumeJobRequest', () {
    test('reads the step to resume from', () {
      expect(ResumeJobRequest.fromJson(const {'fromStep': 2}).fromStep, 2);
      expect(const ResumeJobRequest(fromStep: 2).toJson(), {'fromStep': 2});
    });

    test('has no step by default', () {
      expect(ResumeJobRequest.fromJson(const {}).fromStep, isNull);
      expect(const ResumeJobRequest().toJson(), isEmpty);
    });

    test('compares by value', () {
      expect(
        const ResumeJobRequest(fromStep: 1),
        const ResumeJobRequest(fromStep: 1),
      );
      expect(
        const ResumeJobRequest(fromStep: 1),
        isNot(const ResumeJobRequest()),
      );
    });

    test('rejects a step that is not a number', () {
      expect(
        () => ResumeJobRequest.fromJson(const {'fromStep': 'x'}),
        throwsA(isA<CheckedFromJsonException>()),
      );
    });
  });
}

import 'package:json_annotation/json_annotation.dart';
import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';

void main() {
  final created = DateTime.utc(2026, 10, 13, 9);

  group('RunState', () {
    test('uses snake_case on the wire', () {
      expect(RunState.waitingForApproval.wire, 'waiting_for_approval');
      expect(RunState.queued.wire, 'queued');
    });
  });

  group('DispatchRequest', () {
    test('reads every field', () {
      final request = DispatchRequest.fromJson(const {
        'ref': 'release/1.2.0',
        'app': '.',
        'flavors': ['prod'],
        'platforms': ['android', 'ios'],
        'bump': 'minor',
        'version': '1.3.0',
        'releaseVersion': '1.2.0+45',
        'inputs': {'notes': 'hi'},
      });

      expect(request.ref, 'release/1.2.0');
      expect(request.bump, VersionBump.minor);
      expect(request.inputs, {'notes': 'hi'});
      expect(DispatchRequest.fromJson(request.toJson()), request);
    });

    test('has no inputs by default and leaves out what it lacks', () {
      expect(DispatchRequest.fromJson(const {}).inputs, isEmpty);
      expect(const DispatchRequest().toJson(), {'inputs': <String, dynamic>{}});
    });

    test('rejects a bump it does not know', () {
      expect(
        () => DispatchRequest.fromJson(const {'bump': 'huge'}),
        throwsA(isA<CheckedFromJsonException>()),
      );
      expect(VersionBump.keep.wire, 'keep');
    });
  });

  group('Run', () {
    final run = Run(
      id: 'run_1',
      projectId: 'prj_1',
      workflowId: 'wf_1',
      workflowVersionId: 'wfv_1',
      sha: 'a' * 40,
      ref: 'main',
      state: RunState.waitingForApproval,
      locksProject: true,
      version: '1.2.0',
      build: 45,
      createdAt: created,
      jobs: const [
        RunJob(
          id: 'job_1',
          name: 'prepare',
          stage: 0,
          state: JobState.waitingForApproval,
          capabilities: ['flutter'],
          message: 'Waiting for approval.',
        ),
      ],
    );

    test('serializes its jobs inline', () {
      final json = run.toJson();

      expect(json['state'], 'waiting_for_approval');
      expect(json['createdAt'], '2026-10-13T09:00:00.000Z');
      expect((json['jobs']! as List).single, {
        'id': 'job_1',
        'name': 'prepare',
        'stage': 0,
        'state': 'waiting_for_approval',
        'capabilities': ['flutter'],
        'message': 'Waiting for approval.',
      });
    });

    test('round-trips through JSON', () {
      expect(Run.fromJson(run.toJson()), run);
    });

    test('leaves out what it does not have', () {
      final bare = Run(
        id: 'run_1',
        projectId: 'prj_1',
        workflowId: 'wf_1',
        workflowVersionId: 'wfv_1',
        sha: 'a' * 40,
        state: RunState.queued,
        locksProject: false,
        createdAt: created,
        jobs: const [
          RunJob(id: 'j', name: 'n', stage: 0, state: JobState.queued),
        ],
      );

      expect(bare.toJson().keys, [
        'id',
        'projectId',
        'workflowId',
        'workflowVersionId',
        'sha',
        'state',
        'locksProject',
        'createdAt',
        'jobs',
      ]);
      expect(Run.fromJson(bare.toJson()), bare);
      expect(
        RunJob.fromJson(const {
          'id': 'j',
          'name': 'n',
          'stage': 0,
          'state': 'queued',
        }).capabilities,
        isEmpty,
      );
    });
  });
}

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';

void main() {
  final at = DateTime.utc(2026, 10, 13, 9, 30);

  group('SequencedEvent', () {
    test('serializes seq, time, type and payload', () {
      final event = SequencedEvent(
        seq: 3,
        at: at,
        event: const EngineStarted(version: '0.0.1', apiVersion: '1'),
      );

      expect(event.toJson(), {
        'seq': 3,
        'at': '2026-10-13T09:30:00.000Z',
        'type': 'engine.started',
        'payload': {'version': '0.0.1', 'apiVersion': '1'},
      });
    });

    test('writes local times as UTC', () {
      final local = DateTime.utc(2026, 10, 13, 9, 30).toLocal();
      final event = SequencedEvent(
        seq: 1,
        at: local,
        event: const StreamOpened(),
      );

      expect(event.toJson()['at'], '2026-10-13T09:30:00.000Z');
    });

    test('round-trips every known event', () {
      for (final event in <EngineEvent>[
        const EngineStarted(version: '0.0.1', apiVersion: '1'),
        const StreamOpened(),
        const ProjectAdded(projectId: 'prj_1', fullName: 'o/r'),
        const ProjectScanned(projectId: 'prj_1', errors: 1, warnings: 2),
        const ProjectRemoved(projectId: 'prj_1'),
        const JobStateChanged(
          jobId: 'job_1',
          projectId: 'prj_1',
          state: JobState.waitingForResume,
        ),
        const JobStepChanged(
          jobId: 'job_1',
          ordinal: 2,
          kind: 'command',
          state: StepState.interrupted,
        ),
        const TestRunCompleted(
          jobId: 'job_1',
          projectId: 'prj_1',
          branch: 'main',
          baseline: true,
          failures: 27,
          newFailures: 0,
        ),
        const CredentialSaved(
          credentialId: 'crd_1',
          projectId: 'prj_1',
          kind: CredentialKind.ascKey,
          replaced: true,
        ),
        const CredentialVerified(
          credentialId: 'crd_1',
          projectId: 'prj_1',
          kind: CredentialKind.playSa,
          status: CredentialStatus.rejected,
        ),
        const CredentialExpired(
          credentialId: 'crd_1',
          projectId: 'prj_1',
          kind: CredentialKind.appleId,
          message: 'Revoked.',
        ),
        const CredentialRemoved(
          credentialId: 'crd_1',
          projectId: 'prj_1',
          kind: CredentialKind.slack,
        ),
      ]) {
        final sequenced = SequencedEvent(seq: 9, at: at, event: event);

        expect(SequencedEvent.fromJson(sequenced.toJson()), sequenced);
      }
    });

    test('reads an event of an unknown type as UnknownEvent', () {
      final read = SequencedEvent.fromJson(const {
        'seq': 4,
        'at': '2026-10-13T09:30:00.000Z',
        'type': 'job.renamed',
        'payload': {'id': 'j1'},
      });

      expect(
        read.event,
        const UnknownEvent(type: 'job.renamed', payload: {'id': 'j1'}),
      );
      expect(read.toJson()['type'], 'job.renamed');
      expect(read.toJson()['payload'], {'id': 'j1'});
    });
  });

  group('EngineEvent', () {
    test('exhaustive switch covers every subtype', () {
      String describe(EngineEvent event) => switch (event) {
        EngineStarted() => 'started',
        StreamOpened() => 'opened',
        ProjectAdded() => 'added',
        ProjectScanned() => 'scanned',
        ProjectRemoved() => 'removed',
        JobStateChanged() => 'job',
        JobStepChanged() => 'step',
        TestRunCompleted() => 'tests',
        CredentialSaved() => 'saved',
        CredentialVerified() => 'verified',
        CredentialExpired() => 'expired',
        CredentialRemoved() => 'removed credential',
        UnknownEvent() => 'unknown',
      };

      expect(describe(const StreamOpened()), 'opened');
      expect(
        describe(const ProjectAdded(projectId: 'p', fullName: 'o/r')),
        'added',
      );
      expect(
        describe(const ProjectScanned(projectId: 'p', errors: 0, warnings: 0)),
        'scanned',
      );
      expect(describe(const ProjectRemoved(projectId: 'p')), 'removed');
      expect(
        describe(
          const JobStateChanged(
            jobId: 'j',
            projectId: 'p',
            state: JobState.running,
          ),
        ),
        'job',
      );
      expect(
        describe(
          const JobStepChanged(
            jobId: 'j',
            ordinal: 0,
            kind: 'command',
            state: StepState.running,
          ),
        ),
        'step',
      );
      expect(
        describe(
          const TestRunCompleted(
            jobId: 'j',
            projectId: 'p',
            branch: 'main',
            baseline: false,
            failures: 1,
            newFailures: 1,
          ),
        ),
        'tests',
      );
      expect(
        describe(
          const CredentialSaved(
            credentialId: 'c',
            projectId: 'p',
            kind: CredentialKind.github,
            replaced: false,
          ),
        ),
        'saved',
      );
      expect(
        describe(
          const CredentialVerified(
            credentialId: 'c',
            projectId: 'p',
            kind: CredentialKind.github,
            status: CredentialStatus.verified,
          ),
        ),
        'verified',
      );
      expect(
        describe(
          const CredentialExpired(
            credentialId: 'c',
            projectId: 'p',
            kind: CredentialKind.github,
            message: 'm',
          ),
        ),
        'expired',
      );
      expect(
        describe(
          const CredentialRemoved(
            credentialId: 'c',
            projectId: 'p',
            kind: CredentialKind.github,
          ),
        ),
        'removed credential',
      );
      expect(
        describe(EngineEvent.fromJson('x', const <String, dynamic>{})),
        'unknown',
      );
      expect(
        describe(
          EngineEvent.fromJson('engine.started', const {
            'version': 'v',
            'apiVersion': '1',
          }),
        ),
        'started',
      );
    });

    test('stream.opened has an empty payload and compares by value', () {
      expect(const StreamOpened().payload, isEmpty);
      expect(const StreamOpened().props, isEmpty);
    });
  });
}

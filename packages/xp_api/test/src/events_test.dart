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
        const WorkflowSaved(
          workflowId: 'wf_1',
          projectId: 'prj_1',
          name: 'dev-build',
          version: 2,
        ),
        const WorkflowRemoved(
          workflowId: 'wf_1',
          projectId: 'prj_1',
          name: 'dev-build',
        ),
        const RunDispatched(
          runId: 'run_1',
          projectId: 'prj_1',
          workflowId: 'wf_1',
          jobIds: ['job_1', 'job_2'],
        ),
        ApprovalRequested(
          approvalId: 'apr_1',
          projectId: 'prj_1',
          action: 'prod_release',
          sha: 'a' * 40,
          version: '1.2.3+45',
          expiresAt: at.add(const Duration(hours: 24)),
        ),
        ApprovalRequested(
          approvalId: 'apr_2',
          projectId: 'prj_1',
          action: 'push',
          sha: 'a' * 40,
          expiresAt: at.add(const Duration(hours: 24)),
        ),
        const ApprovalDecided(
          approvalId: 'apr_1',
          projectId: 'prj_1',
          action: 'prod_release',
          state: ApprovalState.approved,
          decidedBy: DecidedBy(
            tokenId: 'tok_1',
            name: 'Mac mini',
            kind: DeviceTokenKind.app,
          ),
        ),
        const ApprovalExpired(
          approvalId: 'apr_1',
          projectId: 'prj_1',
          action: 'prod_release',
        ),
        const ProjectGatesChanged(
          projectId: 'prj_1',
          gates: {'prod_release': true, 'push': false},
          changedBy: DeviceTokenKind.app,
        ),
        const ReleaseCreated(
          releaseId: 'rel_1',
          projectId: 'prj_1',
          flavor: 'prod',
          version: '1.2.0',
          build: 45,
        ),
        const ReleaseStateChanged(
          releaseId: 'rel_1',
          projectId: 'prj_1',
          from: ReleaseState.inReview,
          to: ReleaseState.approved,
        ),
        const ReleaseStoreChanged(
          releaseId: 'rel_1',
          projectId: 'prj_1',
          store: ReleaseStore.apple,
          state: StoreState.inReview,
          source: StatusSource.api,
        ),
        const NotificationRaised(
          kind: NotificationKind.secretsLocked,
          level: NotificationLevel.error,
          title: 'Secrets are locked',
          body: 'Unlock the Keychain.',
        ),
        const NotificationRaised(
          kind: NotificationKind.releaseLive,
          level: NotificationLevel.success,
          title: 'Live',
          body: 'On sale.',
          projectId: 'prj_1',
          releaseId: 'rel_1',
          jobId: 'job_1',
          approvalId: 'apr_1',
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
        WorkflowSaved() => 'workflow saved',
        WorkflowRemoved() => 'workflow removed',
        RunDispatched() => 'run',
        ApprovalRequested() => 'requested',
        ApprovalDecided() => 'decided',
        ApprovalExpired() => 'approval expired',
        ProjectGatesChanged() => 'gates',
        ReleaseCreated() => 'release created',
        ReleaseStateChanged() => 'release state',
        ReleaseStoreChanged() => 'release store',
        NotificationRaised() => 'notification',
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
        describe(
          const WorkflowSaved(
            workflowId: 'w',
            projectId: 'p',
            name: 'n',
            version: 1,
          ),
        ),
        'workflow saved',
      );
      expect(
        describe(
          const WorkflowRemoved(workflowId: 'w', projectId: 'p', name: 'n'),
        ),
        'workflow removed',
      );
      expect(
        describe(
          const RunDispatched(
            runId: 'r',
            projectId: 'p',
            workflowId: 'w',
            jobIds: [],
          ),
        ),
        'run',
      );
      expect(
        describe(
          ApprovalRequested(
            approvalId: 'a',
            projectId: 'p',
            action: 'push',
            sha: 's',
            expiresAt: DateTime.utc(2026),
          ),
        ),
        'requested',
      );
      expect(
        describe(
          const ApprovalDecided(
            approvalId: 'a',
            projectId: 'p',
            action: 'push',
            state: ApprovalState.denied,
            decidedBy: DecidedBy(
              tokenId: 't',
              name: 'n',
              kind: DeviceTokenKind.cli,
            ),
          ),
        ),
        'decided',
      );
      expect(
        describe(
          const ApprovalExpired(approvalId: 'a', projectId: 'p', action: 'x'),
        ),
        'approval expired',
      );
      expect(
        describe(
          const ProjectGatesChanged(
            projectId: 'p',
            gates: {},
            changedBy: DeviceTokenKind.app,
          ),
        ),
        'gates',
      );
      expect(
        describe(
          const ReleaseCreated(
            releaseId: 'r',
            projectId: 'p',
            flavor: 'prod',
            version: '1.0.0',
            build: 1,
          ),
        ),
        'release created',
      );
      expect(
        describe(
          const ReleaseStateChanged(
            releaseId: 'r',
            projectId: 'p',
            from: ReleaseState.live,
            to: ReleaseState.merged,
          ),
        ),
        'release state',
      );
      expect(
        describe(
          const ReleaseStoreChanged(
            releaseId: 'r',
            projectId: 'p',
            store: ReleaseStore.play,
            state: StoreState.live,
            source: StatusSource.manual,
          ),
        ),
        'release store',
      );
      expect(
        describe(
          const NotificationRaised(
            kind: NotificationKind.jobFailed,
            level: NotificationLevel.error,
            title: 't',
            body: 'b',
          ),
        ),
        'notification',
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

    test('notification.raised omits the ids it does not have', () {
      const event = NotificationRaised(
        kind: NotificationKind.releaseRejected,
        level: NotificationLevel.error,
        title: 'Rejected',
        body: 'Apple rejected 1.2.0.',
        projectId: 'prj_1',
      );

      expect(event.type, 'notification.raised');
      expect(event.payload, {
        'kind': 'release_rejected',
        'level': 'error',
        'title': 'Rejected',
        'body': 'Apple rejected 1.2.0.',
        'projectId': 'prj_1',
      });
    });

    test('notification.raised of a newer engine is an unknown event', () {
      for (final payload in <Map<String, dynamic>>[
        {'kind': 'from_the_future', 'level': 'info', 'title': 't', 'body': 'b'},
        {'kind': 'job_failed', 'level': 'loud', 'title': 't', 'body': 'b'},
      ]) {
        expect(
          EngineEvent.fromJson('notification.raised', payload),
          UnknownEvent(type: 'notification.raised', payload: payload),
        );
      }
    });

    test('stream.opened has an empty payload and compares by value', () {
      expect(const StreamOpened().payload, isEmpty);
      expect(const StreamOpened().props, isEmpty);
    });
  });
}

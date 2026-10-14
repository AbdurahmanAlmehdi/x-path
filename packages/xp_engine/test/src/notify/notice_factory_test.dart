import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/approval_harness.dart';
import '../../helpers/notify_harness.dart';

void main() {
  late NotifyHarness h;

  setUp(() async => h = await NotifyHarness.create());

  group('jobs', () {
    test('a production job that failed says why', () async {
      await h.runs.create(runRecord());
      await h.jobs.create(
        jobRecord(runId: 'run_1', message: 'altool rejected the build'),
        const [],
      );

      final notice = await h.factory.describe(
        const JobStateChanged(
          jobId: 'job_1',
          projectId: 'prj_1',
          state: JobState.failed,
        ),
      );

      expect(notice!.kind, NotificationKind.jobFailed);
      expect(notice.level, NotificationLevel.error);
      expect(notice.title, 'Production job failed');
      expect(notice.body, 'octo/demo: Build iOS - altool rejected the build');
      expect(notice.key, 'job_failed:job_1');
      expect(notice.projectId, 'prj_1');
      expect(notice.jobId, 'job_1');
    });

    test('a job of a release is a production job', () async {
      await h.jobs.create(
        jobRecord(
          state: JobState.succeeded,
          releaseId: 'rel_1',
          name: null,
          message: 'ignored when it succeeds',
        ),
        const [],
      );

      final notice = await h.factory.describe(
        const JobStateChanged(
          jobId: 'job_1',
          projectId: 'prj_1',
          state: JobState.succeeded,
        ),
      );

      expect(notice!.kind, NotificationKind.jobSucceeded);
      expect(notice.level, NotificationLevel.success);
      expect(notice.body, 'octo/demo: job_1');
      expect(notice.releaseId, 'rel_1');
    });

    test('a failed job without a message has just its name', () async {
      await h.runs.create(runRecord());
      await h.jobs.create(jobRecord(runId: 'run_1', message: '  '), const []);

      final notice = await h.factory.describe(
        const JobStateChanged(
          jobId: 'job_1',
          projectId: 'prj_1',
          state: JobState.failed,
        ),
      );

      expect(notice!.body, 'octo/demo: Build iOS');
    });

    test('a development job is nothing to tell', () async {
      await h.runs.create(runRecord(locksProject: false));
      await h.jobs.create(jobRecord(runId: 'run_1'), const []);

      expect(
        await h.factory.describe(
          const JobStateChanged(
            jobId: 'job_1',
            projectId: 'prj_1',
            state: JobState.failed,
          ),
        ),
        isNull,
      );
    });

    test('nor is a job with no run and no release, or no record', () async {
      await h.jobs.create(jobRecord(), const []);

      for (final id in ['job_1', 'job_gone']) {
        expect(
          await h.factory.describe(
            JobStateChanged(
              jobId: id,
              projectId: 'prj_1',
              state: JobState.failed,
            ),
          ),
          isNull,
        );
      }
    });

    test('nor is a job that is merely running', () async {
      await h.jobs.create(
        jobRecord(state: JobState.running, releaseId: 'r'),
        [],
      );

      expect(
        await h.factory.describe(
          const JobStateChanged(
            jobId: 'job_1',
            projectId: 'prj_1',
            state: JobState.running,
          ),
        ),
        isNull,
      );
    });

    test('a job of a run that is gone is a development job', () async {
      await h.jobs.create(jobRecord(runId: 'run_gone'), const []);

      expect(
        await h.factory.describe(
          const JobStateChanged(
            jobId: 'job_1',
            projectId: 'prj_1',
            state: JobState.failed,
          ),
        ),
        isNull,
      );
    });
  });

  group('approvals', () {
    test('a request says what, where and how to approve', () async {
      final notice = await h.factory.describe(
        ApprovalRequested(
          approvalId: 'apr_1',
          projectId: 'prj_1',
          action: 'prod_release',
          sha: approvalSha,
          version: '1.2.3+45',
          expiresAt: DateTime.utc(2026, 10, 15, 9, 5),
        ),
      );

      expect(notice!.kind, NotificationKind.approvalRequested);
      expect(notice.level, NotificationLevel.warning);
      expect(notice.title, 'Approval needed: prod release');
      expect(
        notice.body,
        'octo/demo asks to prod release at a1a1a1a 1.2.3+45. Approve in the '
        'app or with `xp approve apr_1` before 2026-10-15 09:05 UTC.',
      );
      expect(notice.approvalId, 'apr_1');
      expect(notice.key, 'approval_requested:apr_1');
    });

    test('a request without a version and with a short commit', () async {
      final notice = await h.factory.describe(
        ApprovalRequested(
          approvalId: 'apr_1',
          projectId: 'prj_gone',
          action: 'push',
          sha: 'abc',
          expiresAt: DateTime.utc(2026, 10, 15),
        ),
      );

      expect(notice!.body, startsWith('prj_gone asks to push at abc. '));
    });

    for (final (state, title, level, verb) in [
      (
        ApprovalState.approved,
        'Approved',
        NotificationLevel.success,
        'approved',
      ),
      (ApprovalState.denied, 'Denied', NotificationLevel.warning, 'denied'),
    ]) {
      test('a decision is told as $verb', () async {
        final notice = await h.factory.describe(
          ApprovalDecided(
            approvalId: 'apr_1',
            projectId: 'prj_1',
            action: 'merge',
            state: state,
            decidedBy: const DecidedBy(
              tokenId: 'tok_1',
              name: 'Mac mini',
              kind: DeviceTokenKind.app,
            ),
          ),
        );

        expect(notice!.kind, NotificationKind.approvalDecided);
        expect(notice.level, level);
        expect(notice.title, '$title: merge');
        expect(
          notice.body,
          'Mac mini (app) $verb the request to merge in octo/demo.',
        );
        expect(notice.key, 'approval_decided:apr_1');
      });
    }

    test('an expiry says it counts as denied', () async {
      final notice = await h.factory.describe(
        const ApprovalExpired(
          approvalId: 'apr_1',
          projectId: 'prj_1',
          action: 'store_submission',
        ),
      );

      expect(notice!.kind, NotificationKind.approvalExpired);
      expect(notice.title, 'Approval expired: store submission');
      expect(notice.body, contains('counts as denied'));
    });
  });

  group('releases', () {
    Future<Notice?> moved(ReleaseState to) => h.factory.describe(
      ReleaseStateChanged(
        releaseId: 'rel_1',
        projectId: 'prj_1',
        from: ReleaseState.inReview,
        to: to,
      ),
    );

    test('a rejection names the stores that rejected it and why', () async {
      await h.releases.create(
        releaseRecord(
          state: ReleaseState.rejected,
          stores: {
            ReleaseStore.apple: const StoreEntry(
              store: ReleaseStore.apple,
              state: StoreState.rejected,
              source: StatusSource.api,
              detail: 'Guideline 2.1',
            ),
            ReleaseStore.play: const StoreEntry(
              store: ReleaseStore.play,
              state: StoreState.rejected,
              source: StatusSource.api,
            ),
            // A store that did not reject it is not named.
          },
        ),
      );

      final notice = await moved(ReleaseState.rejected);

      expect(notice!.kind, NotificationKind.releaseRejected);
      expect(notice.level, NotificationLevel.error);
      expect(notice.title, 'Release rejected');
      expect(
        notice.body,
        'octo/demo prod 1.2.0 (5) was rejected. App Store: Guideline 2.1. '
        'Google Play: rejected. Start a new build of the same version from '
        'the app.',
      );
      expect(notice.releaseId, 'rel_1');
      expect(notice.key, 'release_rejected:rel_1');
    });

    test('approved, live and merged are good news', () async {
      await h.releases.create(releaseRecord(flavor: ''));

      final approved = await moved(ReleaseState.approved);
      final live = await moved(ReleaseState.live);
      final merged = await moved(ReleaseState.merged);

      expect(approved!.kind, NotificationKind.releaseApproved);
      expect(approved.body, 'octo/demo 1.2.0 (5) was approved by the stores.');
      expect(live!.kind, NotificationKind.releaseLive);
      expect(live.body, contains('on sale in every store'));
      expect(merged!.kind, NotificationKind.releaseMerged);
      expect(
        [approved, live, merged].map((n) => n.level),
        everyElement(NotificationLevel.success),
      );
    });

    test('other moves and unknown releases are nothing to tell', () async {
      await h.releases.create(releaseRecord());

      expect(await moved(ReleaseState.inReview), isNull);
      expect(await moved(ReleaseState.abandoned), isNull);
      expect(
        await h.factory.describe(
          const ReleaseStateChanged(
            releaseId: 'rel_gone',
            projectId: 'prj_1',
            from: ReleaseState.approved,
            to: ReleaseState.live,
          ),
        ),
        isNull,
      );
    });
  });

  group('the min_version reminder', () {
    Future<Notice?> live(ReleaseStore store, {String id = 'rel_1'}) =>
        h.factory.describe(
          ReleaseStoreChanged(
            releaseId: id,
            projectId: 'prj_1',
            store: store,
            state: StoreState.live,
            source: StatusSource.api,
          ),
        );

    test('names the iOS variable when the App Store has the build', () async {
      await h.releases.create(releaseRecord());

      final notice = await live(ReleaseStore.apple);

      expect(notice!.kind, NotificationKind.minVersionReminder);
      expect(notice.level, NotificationLevel.info);
      expect(notice.title, 'Raise min_version_ios if this is a forced update');
      expect(
        notice.body,
        'octo/demo prod 1.2.0 (5) is live in the App Store. If it is a '
        'forced update, raise min_version_ios to 1.2.0 in Firebase Remote '
        'Config now. Raising it earlier locks out users who have nothing to '
        'update to.',
      );
      expect(notice.key, 'min_version:rel_1:apple');
    });

    test('names the Android variable when Google Play has it', () async {
      await h.releases.create(releaseRecord());

      final notice = await live(ReleaseStore.play);

      expect(notice!.title, contains('min_version_android'));
      expect(notice.body, contains('is live in Google Play'));
      expect(notice.key, 'min_version:rel_1:play');
    });

    test('says nothing for a release it does not know', () async {
      expect(await live(ReleaseStore.apple, id: 'rel_gone'), isNull);
    });

    test('says nothing before the build is on sale', () async {
      await h.releases.create(releaseRecord());

      expect(
        await h.factory.describe(
          const ReleaseStoreChanged(
            releaseId: 'rel_1',
            projectId: 'prj_1',
            store: ReleaseStore.apple,
            state: StoreState.approved,
            source: StatusSource.api,
          ),
        ),
        isNull,
      );
    });
  });

  test('an expired credential is an error with what the store said', () async {
    final notice = await h.factory.describe(
      const CredentialExpired(
        credentialId: 'crd_1',
        projectId: 'prj_1',
        kind: CredentialKind.ascKey,
        message: 'The key was revoked. Create a new one.',
      ),
    );

    expect(notice!.kind, NotificationKind.credentialExpired);
    expect(notice.level, NotificationLevel.error);
    expect(notice.title, 'Credential expired: asc_key');
    expect(notice.body, 'octo/demo: The key was revoked. Create a new one.');
    expect(notice.key, 'credential_expired:crd_1');
  });

  test('locked secrets are an error that names no project', () {
    final notice = h.factory.secretsLocked();

    expect(notice.kind, NotificationKind.secretsLocked);
    expect(notice.level, NotificationLevel.error);
    expect(notice.projectId, isNull);
    expect(notice.key, 'secrets_locked');
    expect(notice.body, contains('Unlock the Keychain'));
  });

  test('other events are nothing to tell', () async {
    expect(
      await h.factory.describe(
        const EngineStarted(version: '1', apiVersion: '1'),
      ),
      isNull,
    );
  });

  group('the text', () {
    test('hides the secrets the masker knows', () async {
      h.masker.add('s3cret-token');
      final notice = await h.factory.describe(
        const CredentialExpired(
          credentialId: 'crd_1',
          projectId: 'prj_1',
          kind: CredentialKind.slack,
          message: 'POST https://hooks.slack.com/s3cret-token failed.',
        ),
      );

      expect(
        notice!.body,
        'octo/demo: POST https://hooks.slack.com/*** failed.',
      );
    });

    test('is cut to a length a notification can show', () async {
      final notice = await h.factory.describe(
        CredentialExpired(
          credentialId: 'crd_1',
          projectId: 'prj_1',
          kind: CredentialKind.slack,
          message: 'x' * 2000,
        ),
      );

      expect(notice!.body, hasLength(NoticeFactory.maxBodyLength));
      expect(notice.body, endsWith('...'));
    });
  });
}

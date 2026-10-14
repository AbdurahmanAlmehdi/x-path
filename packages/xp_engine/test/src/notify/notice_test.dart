import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  const notice = Notice(
    kind: NotificationKind.releaseLive,
    level: NotificationLevel.success,
    title: 'Release live',
    body: 'octo/demo 1.2.0 is on sale.',
    key: 'release_live:rel_1',
    projectId: 'prj_1',
    releaseId: 'rel_1',
    jobId: 'job_1',
    approvalId: 'apr_1',
  );

  test('becomes the event the app shows', () {
    expect(
      notice.toEvent(),
      const NotificationRaised(
        kind: NotificationKind.releaseLive,
        level: NotificationLevel.success,
        title: 'Release live',
        body: 'octo/demo 1.2.0 is on sale.',
        projectId: 'prj_1',
        releaseId: 'rel_1',
        jobId: 'job_1',
        approvalId: 'apr_1',
      ),
    );
  });

  test('compares by value', () {
    expect(
      notice,
      const Notice(
        kind: NotificationKind.releaseLive,
        level: NotificationLevel.success,
        title: 'Release live',
        body: 'octo/demo 1.2.0 is on sale.',
        key: 'release_live:rel_1',
        projectId: 'prj_1',
        releaseId: 'rel_1',
        jobId: 'job_1',
        approvalId: 'apr_1',
      ),
    );
    expect(
      notice,
      isNot(
        const Notice(
          kind: NotificationKind.releaseLive,
          level: NotificationLevel.success,
          title: 'Release live',
          body: 'octo/demo 1.2.0 is on sale.',
          key: 'release_live:rel_2',
        ),
      ),
    );
  });

  test('becomes a Slack message with the title in bold', () {
    expect(notice.slackText, '*Release live*\nocto/demo 1.2.0 is on sale.');
  });

  test('escapes what Slack reads as markup', () {
    const risky = Notice(
      kind: NotificationKind.jobFailed,
      level: NotificationLevel.error,
      title: 'a & b',
      body: '<!channel> x > y',
      key: 'k',
    );

    expect(risky.slackText, '*a &amp; b*\n&lt;!channel&gt; x &gt; y');
  });
}

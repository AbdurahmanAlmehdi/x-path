import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/release_harness.dart';

void main() {
  test('reads the texts of the release a job belongs to', () async {
    final h = await ReleaseHarness.create();
    final id = await h.open();
    await h.service.setTexts(
      id,
      const ReleaseTexts(whatsNew: 'New', whatToTest: 'Try it'),
      by: owner(),
    );
    final job = await h.addJob(id, const []);
    await h.jobs.create(
      JobRecord(
        id: 'job_free',
        workflowVersionId: 'wfv_1',
        projectId: 'prj_1',
        name: 'No release',
        state: JobState.running,
        createdAt: h.clock.now(),
      ),
      const [],
    );
    await h.jobs.create(
      JobRecord(
        id: 'job_lost',
        workflowVersionId: 'wfv_1',
        projectId: 'prj_1',
        releaseId: 'rel_gone',
        name: 'Gone',
        state: JobState.running,
        createdAt: h.clock.now(),
      ),
      const [],
    );
    final texts = JobReleaseTexts(jobs: h.jobs, releases: h.releases);

    expect(
      await texts.ofJob(job),
      const ReleaseTexts(whatsNew: 'New', whatToTest: 'Try it'),
    );
    expect(await texts.ofJob('job_free'), isNull);
    expect(await texts.ofJob('job_lost'), isNull);
    expect(await texts.ofJob('job_none'), isNull);
  });
}

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/test_run_records.dart';

void main() {
  late InMemoryTestRunRepository runs;
  late InMemoryJobRepository jobs;
  late InMemoryProjectRepository projects;
  late TestRunService service;

  setUp(() async {
    runs = InMemoryTestRunRepository();
    jobs = InMemoryJobRepository();
    projects = InMemoryProjectRepository();
    service = TestRunService(runs: runs, jobs: jobs, projects: projects);
    for (final id in ['job_1', 'job_2']) {
      await jobs.create(
        JobRecord(
          id: id,
          workflowVersionId: 'wfv_1',
          projectId: 'prj_1',
          state: JobState.succeeded,
          createdAt: DateTime.utc(2026),
        ),
        const [],
      );
    }
    await runs.save(
      testRunRecord(
        tests: {
          'a passes': TestStatus.passed,
          'b fails': TestStatus.failed,
          'c throws': TestStatus.errored,
          'd skipped': TestStatus.skipped,
          'e fails': TestStatus.failed,
          'f passes': TestStatus.passed,
        },
      ),
    );
  });

  group('forJob', () {
    test('lists the failures unless asked for other statuses', () async {
      final page = await service.forJob('job_1');

      expect(page.total, 3);
      expect(page.offset, 0);
      expect(page.tests.map((test) => test.name), [
        'b fails',
        'c throws',
        'e fails',
      ]);
      expect(page.run.jobId, 'job_1');
    });

    test('lists the statuses asked for', () async {
      final page = await service.forJob(
        'job_1',
        statuses: {TestStatus.passed, TestStatus.skipped},
      );

      expect(page.tests.map((test) => test.name), [
        'a passes',
        'd skipped',
        'f passes',
      ]);
    });

    test('pages through the tests', () async {
      final first = await service.forJob('job_1', limit: 2);
      final second = await service.forJob('job_1', limit: 2, offset: 2);
      final past = await service.forJob('job_1', limit: 2, offset: 9);

      expect(first.tests.map((test) => test.name), ['b fails', 'c throws']);
      expect(first.total, 3);
      expect(second.tests.map((test) => test.name), ['e fails']);
      expect(second.offset, 2);
      expect(past.tests, isEmpty);
      expect(past.total, 3);
    });

    test('keeps the message of a failure', () async {
      final page = await service.forJob('job_1');

      expect(page.tests.first.message, 'it failed');
    });

    test('fails for a job that does not exist', () async {
      expect(
        () => service.forJob('job_nope'),
        throwsA(isA<JobNotFoundException>()),
      );
    });

    test('fails for a job without a test run', () async {
      await expectLater(
        service.forJob('job_2'),
        throwsA(
          isA<TestRunNotFoundException>().having(
            (error) => error.message,
            'message',
            'Job job_2 has no test run.',
          ),
        ),
      );
      expect(
        const TestRunNotFoundException('job_2').toString(),
        'TestRunNotFoundException: Job job_2 has no test run.',
      );
    });
  });

  group('baselines', () {
    test('lists the baselines of a project', () async {
      await projects.add(
        ProjectRecord(
          id: 'prj_1',
          githubRepoId: 1,
          fullName: 'o/r',
          remote: 'https://github.com/o/r.git',
          githubDefaultBranch: 'main',
          scan: const ProjectProfile(),
          findings: const [],
          scannedAt: DateTime.utc(2026),
        ),
      );

      final baselines = await service.baselines('prj_1');

      expect(baselines.map((run) => run.jobId), ['job_1']);
    });

    test('fails for a project that does not exist', () {
      expect(
        () => service.baselines('prj_nope'),
        throwsA(isA<ProjectNotFoundException>()),
      );
    });
  });
}

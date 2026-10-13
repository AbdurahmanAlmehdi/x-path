import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/test_run_records.dart';

void main() {
  late InMemoryTestRunRepository repository;

  setUp(() => repository = InMemoryTestRunRepository());

  Future<TestRunRecord?> baseline({
    String project = 'prj_1',
    String app = '.',
    String branch = 'main',
  }) => repository.baseline(projectId: project, appPath: app, branch: branch);

  test('keeps one run per job', () async {
    await repository.save(testRunRecord());
    await repository.save(testRunRecord(id: 'tst_2', baseline: false));

    expect((await repository.forJob('job_1'))?.id, 'tst_2');
    expect(await repository.forJob('job_2'), isNull);
  });

  test(
    'the baseline is the latest baseline run of that app and branch',
    () async {
      await repository.save(
        testRunRecord(id: 'old', createdAt: DateTime.utc(2025)),
      );
      await repository.save(
        testRunRecord(
          id: 'new',
          jobId: 'job_2',
          createdAt: DateTime.utc(2026, 3),
        ),
      );
      await repository.save(
        testRunRecord(
          id: 'mid',
          jobId: 'job_3',
          createdAt: DateTime.utc(2026, 2),
        ),
      );
      await repository.save(
        testRunRecord(
          id: 'not a baseline',
          jobId: 'job_4',
          baseline: false,
          createdAt: DateTime.utc(2026, 4),
        ),
      );

      expect((await baseline())?.id, 'new');
    },
  );

  test('a baseline of another project, app or branch is no baseline', () async {
    await repository.save(testRunRecord());

    expect(await baseline(project: 'prj_2'), isNull);
    expect(await baseline(app: 'apps/mobile'), isNull);
    expect(await baseline(branch: 'develop'), isNull);
  });

  test('lists the current baseline of every app and branch', () async {
    await repository.save(
      testRunRecord(id: 'a-main', jobId: 'j1', appPath: 'apps/a'),
    );
    await repository.save(
      testRunRecord(
        id: 'a-main-new',
        jobId: 'j2',
        appPath: 'apps/a',
        createdAt: DateTime.utc(2026, 11),
      ),
    );
    await repository.save(
      testRunRecord(id: 'a-dev', jobId: 'j3', appPath: 'apps/a', branch: 'dev'),
    );
    await repository.save(testRunRecord(id: 'root', jobId: 'j4'));
    await repository.save(
      testRunRecord(id: 'other project', jobId: 'j5', projectId: 'prj_2'),
    );
    await repository.save(
      testRunRecord(id: 'branch run', jobId: 'j6', baseline: false),
    );

    expect(
      [for (final run in await repository.baselines('prj_1')) run.id],
      ['root', 'a-dev', 'a-main-new'],
    );
  });
}

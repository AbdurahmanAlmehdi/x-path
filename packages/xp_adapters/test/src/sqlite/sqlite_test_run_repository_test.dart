import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

final _created = DateTime.utc(2026, 10, 13, 9, 30, 15, 123, 456);

TestRunRecord _run(
  String id, {
  String jobId = 'job_1',
  String projectId = 'prj_1',
  String branch = 'main',
  String appPath = '.',
  bool baseline = true,
  DateTime? createdAt,
  Map<String, TestStatus> tests = const {
    'ok': TestStatus.passed,
    'bad': TestStatus.failed,
    'skipped': TestStatus.skipped,
  },
}) {
  final results = TestRunResults.of([
    for (final MapEntry(:key, :value) in tests.entries)
      TestCase(
        suite: 'test/a_test.dart',
        name: key,
        status: value,
        message: value.isFailure ? 'Expected: <2>\n  Actual: <1>\n' : null,
        stackTrace: value.isFailure ? 'test/a_test.dart 8:7  main' : null,
      ),
  ]);
  return TestRunRecord(
    id: id,
    jobId: jobId,
    projectId: projectId,
    branch: branch,
    appPath: appPath,
    baseline: baseline,
    createdAt: createdAt ?? _created,
    results: results,
    diff: diffTestRuns(results, null),
  );
}

void main() {
  late SqliteDatabase database;
  late SqliteTestRunRepository repository;

  setUp(() {
    database = SqliteDatabase.openInMemory();
    addTearDown(database.close);
    database.connection
      ..execute(
        'INSERT INTO project (id, github_repo_id, remote, '
        "default_base_branch) VALUES ('prj_1', 1, 'r', 'main')",
      )
      ..execute(
        'INSERT INTO workflow (id, project_id, name) '
        "VALUES ('wf_1', 'prj_1', 'w')",
      )
      ..execute(
        'INSERT INTO workflow_version (id, workflow_id, version, yaml) '
        "VALUES ('wfv_1', 'wf_1', 1, '')",
      );
    for (var i = 1; i <= 6; i++) {
      database.connection.execute(
        'INSERT INTO job (id, workflow_version_id, project_id, state) '
        "VALUES ('job_$i', 'wfv_1', 'prj_1', 'running')",
      );
    }
    repository = SqliteTestRunRepository(database);
  });

  test('stores a run and reads it back with microsecond time', () async {
    await repository.save(_run('tst_1', appPath: 'apps/mobile'));

    expect(
      await repository.forJob('job_1'),
      _run('tst_1', appPath: 'apps/mobile'),
    );
    expect(await repository.forJob('job_2'), isNull);
  });

  test('keeps the tests as one compact JSON document', () async {
    await repository.save(_run('tst_1'));

    final row = database.connection
        .select('SELECT results, baseline FROM test_run')
        .single;

    expect(row['baseline'], 1);
    expect(row['results'], contains('"suites"'));
    expect(row['results'], contains('"diff"'));
    expect(row['results'], contains('"passed":["ok"]'));
  });

  test('replaces the run of a job', () async {
    await repository.save(_run('tst_1'));
    await repository.save(
      _run('tst_1', baseline: false, tests: const {'ok': TestStatus.passed}),
    );

    expect(
      database.connection
          .select('SELECT count(*) AS n FROM test_run')
          .single['n'],
      1,
    );
    final run = await repository.forJob('job_1');
    expect(run?.baseline, isFalse);
    expect(run?.results.tests, hasLength(1));
  });

  test('a run needs a job that exists', () {
    expect(
      () => repository.save(_run('tst_1', jobId: 'job_nope')),
      throwsA(isA<SqliteException>()),
    );
  });

  test('the baseline is the latest baseline of that app and branch', () async {
    await repository.save(_run('old', createdAt: DateTime.utc(2026)));
    await repository.save(
      _run('new', jobId: 'job_2', createdAt: DateTime.utc(2026, 3)),
    );
    await repository.save(
      _run('mid', jobId: 'job_3', createdAt: DateTime.utc(2026, 2)),
    );
    await repository.save(
      _run(
        'branch run',
        jobId: 'job_4',
        baseline: false,
        createdAt: DateTime.utc(2026, 4),
      ),
    );

    final latest = await repository.baseline(
      projectId: 'prj_1',
      appPath: '.',
      branch: 'main',
    );

    expect(latest?.id, 'new');
  });

  test('breaks a tie of time by the order of storing', () async {
    await repository.save(_run('first'));
    await repository.save(_run('second', jobId: 'job_2'));

    final latest = await repository.baseline(
      projectId: 'prj_1',
      appPath: '.',
      branch: 'main',
    );

    expect(latest?.id, 'second');
  });

  test('another project, app or branch has no baseline', () async {
    await repository.save(_run('tst_1'));

    for (final (project, app, branch) in [
      ('prj_2', '.', 'main'),
      ('prj_1', 'apps/mobile', 'main'),
      ('prj_1', '.', 'develop'),
    ]) {
      expect(
        await repository.baseline(
          projectId: project,
          appPath: app,
          branch: branch,
        ),
        isNull,
      );
    }
  });

  test('lists the current baseline of every app and branch', () async {
    await repository.save(_run('a-main', appPath: 'apps/a'));
    await repository.save(
      _run(
        'a-main-new',
        jobId: 'job_2',
        appPath: 'apps/a',
        createdAt: DateTime.utc(2026, 11),
      ),
    );
    await repository.save(
      _run('a-dev', jobId: 'job_3', appPath: 'apps/a', branch: 'dev'),
    );
    await repository.save(_run('root', jobId: 'job_4'));
    await repository.save(_run('same time', jobId: 'job_5', appPath: 'apps/a'));
    await repository.save(_run('not one', jobId: 'job_6', baseline: false));

    final baselines = await repository.baselines('prj_1');

    expect(
      [for (final run in baselines) run.id],
      ['root', 'a-dev', 'a-main-new'],
    );
    expect(await repository.baselines('prj_2'), isEmpty);
  });

  test('a run is deleted with its job', () async {
    await repository.save(_run('tst_1'));

    database.connection.execute("DELETE FROM job WHERE id = 'job_1'");

    expect(await repository.forJob('job_1'), isNull);
  });
}

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

final _created = DateTime.utc(2026, 10, 13, 9, 30, 15, 123, 456);

RunRecord _run(String id, {bool held = false, DateTime? at}) => RunRecord(
  id: id,
  projectId: 'prj_1',
  workflowId: 'wf_1',
  workflowVersionId: 'wfv_1',
  sha: 'a' * 40,
  ref: 'main',
  locksProject: true,
  lockHeld: held,
  version: '1.2.3',
  build: 45,
  request: const {
    'ref': 'main',
    'inputs': {'notes': 'hi'},
  },
  createdAt: at ?? _created,
);

void main() {
  late SqliteDatabase database;
  late SqliteRunRepository repository;
  late SqliteJobRepository jobs;

  setUp(() {
    database = SqliteDatabase.openInMemory();
    addTearDown(database.close);
    database.connection
      ..execute(
        'INSERT INTO project (id, host, source_key, github_repo_id, remote, '
        'default_base_branch) '
        "VALUES ('prj_1', 'github.com', '1', 1, 'r', 'main')",
      )
      ..execute(
        'INSERT INTO workflow (id, project_id, name) '
        "VALUES ('wf_1', 'prj_1', 'w')",
      )
      ..execute(
        'INSERT INTO workflow_version (id, workflow_id, version, yaml) '
        "VALUES ('wfv_1', 'wf_1', 1, '')",
      );
    repository = SqliteRunRepository(database);
    jobs = SqliteJobRepository(database);
  });

  test('stores a run and reads it back, times to the microsecond', () async {
    await repository.create(_run('run_1'));

    final read = (await repository.get('run_1'))!;

    expect(read, _run('run_1'));
    expect(read.createdAt.isUtc, isTrue);
    expect(read.request['inputs'], {'notes': 'hi'});
    expect(await repository.get('run_x'), isNull);
  });

  test('stores a run without a ref, version or build', () async {
    await repository.create(
      RunRecord(
        id: 'run_2',
        projectId: 'prj_1',
        workflowId: 'wf_1',
        workflowVersionId: 'wfv_1',
        sha: 'b' * 40,
        locksProject: false,
        createdAt: _created,
      ),
    );

    final read = (await repository.get('run_2'))!;

    expect(read.ref, isNull);
    expect(read.version, isNull);
    expect(read.build, isNull);
    expect(read.locksProject, isFalse);
    expect(read.lockHeld, isFalse);
    expect(read.request, isEmpty);
  });

  test('refuses a project or workflow version that is not there', () async {
    await expectLater(
      repository.create(
        RunRecord(
          id: 'run_3',
          projectId: 'prj_x',
          workflowId: 'wf_1',
          workflowVersionId: 'wfv_1',
          sha: 'a',
          locksProject: false,
          createdAt: _created,
        ),
      ),
      throwsA(isA<SqliteException>()),
    );
  });

  test('records who holds the project lock, oldest first', () async {
    await repository.create(_run('run_1'));
    await repository.create(
      _run('run_2', at: _created.add(const Duration(seconds: 1))),
    );
    await repository.create(
      _run('run_3', at: _created.subtract(const Duration(seconds: 1))),
    );
    expect(await repository.held(), isEmpty);

    await repository.setLockHeld('run_2', held: true);
    await repository.setLockHeld('run_3', held: true);

    expect((await repository.held()).map((run) => run.id), ['run_3', 'run_2']);
    expect((await repository.get('run_2'))!.lockHeld, isTrue);
    await repository.setLockHeld('run_2', held: false);
    expect((await repository.held()).map((run) => run.id), ['run_3']);
  });

  test(
    'the jobs of a run come by stage, then in the order they were made',
    () async {
      await repository.create(_run('run_1'));
      JobRecord job(String id, {String? runId, int stage = 0}) => JobRecord(
        id: id,
        workflowVersionId: 'wfv_1',
        projectId: 'prj_1',
        state: JobState.queued,
        createdAt: _created,
        runId: runId,
        stage: stage,
        name: 'job $id',
        capabilities: const ['flutter', 'ios-sign'],
      );
      for (final record in [
        job('job_c', runId: 'run_1', stage: 1),
        job('job_a', runId: 'run_1'),
        job('job_x'),
        job('job_b', runId: 'run_1'),
      ]) {
        await jobs.create(record, const []);
      }

      final read = await jobs.forRun('run_1');

      expect(read.map((j) => j.id), ['job_a', 'job_b', 'job_c']);
      expect(read.first.name, 'job job_a');
      expect(read.first.capabilities, ['flutter', 'ios-sign']);
      expect(read.last.stage, 1);
      expect(read.first.runId, 'run_1');
      expect((await jobs.get('job_x'))!.runId, isNull);
      expect(await jobs.forRun('run_9'), isEmpty);
    },
  );
}

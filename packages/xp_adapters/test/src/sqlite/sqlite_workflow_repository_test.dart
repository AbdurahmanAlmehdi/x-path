import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

final _at = DateTime.utc(2026, 10, 13, 9, 30, 15, 123, 456);

WorkflowRecord _workflow(String id, String name, {bool builtin = false}) =>
    WorkflowRecord(id: id, projectId: 'prj_1', name: name, builtin: builtin);

WorkflowVersionRecord _version(String workflow, int number) =>
    WorkflowVersionRecord(
      id: 'wfv_${workflow}_$number',
      workflowId: workflow,
      version: number,
      yaml: 'schema: 1\n# $number',
      createdAt: _at,
    );

void main() {
  late SqliteDatabase database;
  late SqliteWorkflowRepository repository;

  setUp(() {
    database = SqliteDatabase.openInMemory();
    addTearDown(database.close);
    database.connection
      ..execute(
        'INSERT INTO project (id, github_repo_id, remote, '
        "default_base_branch) VALUES ('prj_1', 1, 'r', 'main')",
      )
      ..execute(
        'INSERT INTO project (id, github_repo_id, remote, '
        "default_base_branch) VALUES ('prj_2', 2, 'r', 'main')",
      );
    repository = SqliteWorkflowRepository(database);
  });

  test('stores a workflow with its first version', () async {
    await repository.create(
      _workflow('wf_1', 'dev-build', builtin: true),
      _version('wf_1', 1),
    );

    expect(
      await repository.get('wf_1'),
      _workflow('wf_1', 'dev-build', builtin: true),
    );
    expect(await repository.versions('wf_1'), [_version('wf_1', 1)]);
    expect(await repository.get('wf_x'), isNull);
  });

  test('keeps the time of a version to the microsecond, in UTC', () async {
    await repository.create(_workflow('wf_1', 'a'), _version('wf_1', 1));

    final read = (await repository.versions('wf_1')).single;

    expect(read.createdAt, _at);
    expect(read.createdAt.isUtc, isTrue);
  });

  test('lists the workflows of a project by name', () async {
    await repository.create(_workflow('wf_b', 'b'), _version('wf_b', 1));
    await repository.create(_workflow('wf_a', 'a'), _version('wf_a', 1));
    await repository.create(
      const WorkflowRecord(
        id: 'wf_c',
        projectId: 'prj_2',
        name: 'a',
        builtin: false,
      ),
      _version('wf_c', 1),
    );

    expect((await repository.list('prj_1')).map((w) => w.id), ['wf_a', 'wf_b']);
    expect((await repository.list('prj_2')).map((w) => w.id), ['wf_c']);
    expect((await repository.findByName('prj_1', 'a'))!.id, 'wf_a');
    expect((await repository.findByName('prj_2', 'a'))!.id, 'wf_c');
    expect(await repository.findByName('prj_1', 'c'), isNull);
  });

  test('refuses two workflows of one name in a project', () async {
    await repository.create(_workflow('wf_1', 'a'), _version('wf_1', 1));

    await expectLater(
      repository.create(_workflow('wf_2', 'a'), _version('wf_2', 1)),
      throwsA(isA<SqliteException>()),
    );
    expect(await repository.get('wf_2'), isNull, reason: 'stored nothing');
    expect(await repository.versions('wf_2'), isEmpty);
  });

  test('numbers the versions one after the other', () async {
    await repository.create(_workflow('wf_1', 'a'), _version('wf_1', 1));

    final second = await repository.addVersion(
      workflowId: 'wf_1',
      versionId: 'wfv_2',
      yaml: 'two',
      createdAt: _at,
    );
    final third = await repository.addVersion(
      workflowId: 'wf_1',
      versionId: 'wfv_3',
      yaml: 'three',
      createdAt: _at,
    );

    expect((second.version, third.version), (2, 3));
    expect((await repository.versions('wf_1')).map((v) => v.yaml), [
      'schema: 1\n# 1',
      'two',
      'three',
    ]);
    expect((await repository.versionById('wfv_3'))!.version, 3);
    expect(await repository.versionById('wfv_x'), isNull);
  });

  test('deletes a workflow with its versions', () async {
    await repository.create(_workflow('wf_1', 'a'), _version('wf_1', 1));

    expect(await repository.remove('wf_1'), isTrue);
    expect(await repository.remove('wf_1'), isFalse);
    expect(await repository.versions('wf_1'), isEmpty);
  });

  test('keeps a workflow that a job ran', () async {
    await repository.create(_workflow('wf_1', 'a'), _version('wf_1', 1));
    await SqliteJobRepository(database).create(
      JobRecord(
        id: 'job_1',
        workflowVersionId: 'wfv_wf_1_1',
        projectId: 'prj_1',
        state: JobState.queued,
        createdAt: _at,
      ),
      const [],
    );

    await expectLater(
      repository.remove('wf_1'),
      throwsA(isA<WorkflowInUseException>()),
    );
    expect(await repository.get('wf_1'), isNotNull);
  });

  test('is removed with its project', () async {
    await repository.create(_workflow('wf_1', 'a'), _version('wf_1', 1));

    database.connection.execute("DELETE FROM project WHERE id = 'prj_1'");

    expect(await repository.get('wf_1'), isNull);
  });
}

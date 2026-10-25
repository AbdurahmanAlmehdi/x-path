import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';

/// What the version 1 schema enforces, beyond its shape (which the snapshot
/// tests pin).
void main() {
  late Database db;

  setUp(() {
    final database = SqliteDatabase.openInMemory();
    addTearDown(database.close);
    db = database.connection;
  });

  void insertProject([String id = 'p1', int repoId = 1]) => db.execute(
    'INSERT INTO project '
    '(id, host, source_key, github_repo_id, remote, default_base_branch) '
    "VALUES (?, 'github.com', ?, ?, 'git@github.com:o/r.git', 'main')",
    [id, '$repoId', repoId],
  );

  void insertApp([String id = 'a1', String project = 'p1']) => db.execute(
    'INSERT INTO app (id, project_id, path, framework, store_country) '
    "VALUES (?, ?, 'apps/$id', 'flutter', 'us')",
    [id, project],
  );

  void insertFlavor() => db.execute(
    'INSERT INTO flavor (id, app_id, name, entrypoint) '
    "VALUES ('f1', 'a1', 'prod', 'lib/main_prod.dart')",
  );

  void insertWorkflowVersion() => db
    ..execute(
      "INSERT INTO workflow (id, project_id, name) VALUES ('w1', 'p1', 'ship')",
    )
    ..execute(
      'INSERT INTO workflow_version (id, workflow_id, version, yaml) '
      "VALUES ('wv1', 'w1', 1, 'steps: []')",
    );

  void insertJob({String? release, String? runner}) => db.execute(
    'INSERT INTO job '
    '(id, workflow_version_id, project_id, release_id, state, runner_id) '
    "VALUES ('j1', 'wv1', 'p1', ?, 'queued', ?)",
    [release, runner],
  );

  int count(String table) =>
      db.select('SELECT count(*) FROM $table').single.columnAt(0) as int;

  test('every entity of the data model has a table', () {
    final tables = db
        .select("SELECT name FROM sqlite_schema WHERE type = 'table'")
        .map((row) => row['name']);

    expect(
      tables,
      containsAll([
        'device_token',
        'project',
        'app',
        'flavor',
        'credential',
        'credential_assignment',
        'workflow',
        'workflow_version',
        'release',
        'job',
        'job_step',
        'artifact',
        'approval',
        'runner',
        'test_run',
        'event',
      ]),
    );
  });

  test('foreign keys are enforced', () {
    expect(() => insertApp('a1', 'missing'), throwsA(isA<SqliteException>()));
  });

  test('deleting a project deletes what belongs to it', () {
    insertProject();
    insertApp();
    insertFlavor();
    insertWorkflowVersion();
    db
      ..execute(
        'INSERT INTO credential (id, name, kind, secret_key) '
        "VALUES ('c1', 'Key', 'asc_key', 'k')",
      )
      ..execute(
        'INSERT INTO credential_assignment (flavor_id, kind, credential_id) '
        "VALUES ('f1', 'asc_key', 'c1')",
      )
      ..execute(
        'INSERT INTO approval (id, project_id, action, state) '
        "VALUES ('ap1', 'p1', 'promote', 'pending')",
      )
      ..execute("DELETE FROM project WHERE id = 'p1'");

    for (final table in [
      'app',
      'flavor',
      'credential_assignment',
      'workflow',
      'workflow_version',
      'approval',
    ]) {
      expect(count(table), 0, reason: table);
    }
  });

  test('history is not deleted from under a release or a job', () {
    insertProject();
    insertApp();
    insertWorkflowVersion();
    db.execute(
      'INSERT INTO release (id, app_id, version, build, state) '
      "VALUES ('r1', 'a1', '1.0.0', 1, 'draft')",
    );
    insertJob(release: 'r1');

    expect(
      () => db.execute("DELETE FROM app WHERE id = 'a1'"),
      throwsA(isA<SqliteException>()),
    );
    expect(
      () => db.execute("DELETE FROM project WHERE id = 'p1'"),
      throwsA(isA<SqliteException>()),
    );
  });

  test('deleting a job deletes its steps, artifacts and test run', () {
    insertProject();
    insertWorkflowVersion();
    insertJob();
    db
      ..execute(
        'INSERT INTO job_step (id, job_id, ordinal, kind, state, result) '
        "VALUES ('s1', 'j1', 0, 'guard', 'done', '{\"ok\":true}')",
      )
      ..execute(
        'INSERT INTO artifact (id, job_id, kind, path, size, sha256) '
        "VALUES ('ar1', 'j1', 'ipa', 'a.ipa', 10, 'abc')",
      )
      ..execute(
        'INSERT INTO test_run (id, job_id, branch) '
        "VALUES ('t1', 'j1', 'main')",
      )
      ..execute("DELETE FROM job WHERE id = 'j1'");

    expect(
      [count('job_step'), count('artifact'), count('test_run')],
      [0, 0, 0],
    );
  });

  test('deleting a runner releases its jobs', () {
    insertProject();
    insertWorkflowVersion();
    db.execute("INSERT INTO runner (id, name) VALUES ('rn1', 'mini')");
    insertJob(runner: 'rn1');

    db.execute("DELETE FROM runner WHERE id = 'rn1'");

    expect(db.select('SELECT runner_id FROM job').single['runner_id'], isNull);
  });

  test('JSON columns must hold valid JSON', () {
    expect(
      () => db.execute(
        'INSERT INTO project (id, host, source_key, github_repo_id, remote, '
        'default_base_branch, gates) '
        "VALUES ('p', 'github.com', '1', 1, 'r', 'main', '{nope')",
      ),
      throwsA(isA<SqliteException>()),
    );
    expect(
      () => db.execute(
        "INSERT INTO event (type, payload, at) VALUES ('t', 'nope', 0)",
      ),
      throwsA(isA<SqliteException>()),
    );
    insertProject();
    expect(
      db.select('SELECT release_model, gates FROM project').single.values,
      ['{}', '{}'],
    );
  });

  test('the scan columns of version 2 default to an empty scan', () {
    insertProject();

    expect(
      db
          .select(
            'SELECT full_name, local_path, github_default_branch, scan, '
            'findings, scanned_at, edits FROM project',
          )
          .single
          .values,
      ['', null, '', '{}', '[]', 0, '{}'],
    );
    for (final column in ['scan', 'findings', 'edits']) {
      expect(
        () => db.execute("UPDATE project SET $column = 'nope'"),
        throwsA(isA<SqliteException>()),
        reason: column,
      );
    }
  });

  test('enumerated columns refuse unknown values', () {
    expect(
      () => db.execute(
        'INSERT INTO device_token (id, name, kind, hash, created_at) '
        "VALUES ('t', 'n', 'robot', 'h', 0)",
      ),
      throwsA(isA<SqliteException>()),
    );
    insertProject();
    insertApp();
    insertFlavor();
    expect(
      () => db.execute(
        'INSERT INTO credential (id, name, kind, secret_key) '
        "VALUES ('c', 'c', 'password', 'k')",
      ),
      throwsA(isA<SqliteException>()),
    );
  });

  test('names are unique where they identify something', () {
    insertProject();
    insertApp();

    expect(() => insertProject('p2'), throwsA(isA<SqliteException>()));
    expect(
      () => db.execute(
        'INSERT INTO app (id, project_id, path, framework, store_country) '
        "VALUES ('a2', 'p1', 'apps/a1', 'flutter', 'us')",
      ),
      throwsA(isA<SqliteException>()),
    );
  });

  test('STRICT tables refuse a value of the wrong type', () {
    expect(
      () => db.execute(
        'INSERT INTO device_token (id, name, kind, hash, created_at) '
        "VALUES ('t', 'n', 'app', 'h', 'yesterday')",
      ),
      throwsA(isA<SqliteException>()),
    );
  });

  test('event sequence numbers keep growing after the last row is deleted', () {
    db
      ..execute("INSERT INTO event (type, payload, at) VALUES ('a', '{}', 0)")
      ..execute("INSERT INTO event (type, payload, at) VALUES ('b', '{}', 0)")
      ..execute('DELETE FROM event')
      ..execute("INSERT INTO event (type, payload, at) VALUES ('c', '{}', 0)");

    expect(db.select('SELECT seq FROM event').single['seq'], 3);
  });
}

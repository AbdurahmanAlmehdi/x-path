import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_api/xp_api.dart';

import '../../helpers/schema_dump.dart';

/// Set `UPDATE_GOLDENS=1` to rewrite the golden file of every version from
/// the migrations. Review the diff: a released golden must never change.
final _update = Platform.environment['UPDATE_GOLDENS'] == '1';

String _golden(int version) => snapshotFile(version).readAsStringSync();

void main() {
  final latest = engineMigrations.length;

  setUpAll(() {
    if (!_update) return;
    for (final migration in engineMigrations) {
      final database = SqliteDatabase.openInMemory(
        migrations: engineMigrations.take(migration.version).toList(),
      );
      snapshotFile(migration.version)
          .writeAsStringSync(dumpSchema(database.connection));
      database.close();
    }
  });

  group('engineMigrations', () {
    test('count up from 1', () {
      expect(
        engineMigrations.map((migration) => migration.version),
        List.generate(latest, (i) => i + 1),
      );
    });

    test('have exactly one golden schema each', () {
      expect(snapshotVersions(), List.generate(latest, (i) => i + 1));
    });

    test('are all valid SQL that runs in order', () {
      final database = SqliteDatabase.openInMemory();
      addTearDown(database.close);

      expect(database.connection.userVersion, latest);
    });
  });

  group('v14 named credentials', () {
    /// A database at version 13 with three projects' flavors and their
    /// per-flavor credentials, then migrated.
    ({SqliteDatabase database, List<String> notes}) migrate(String path) {
      sqlite3.open(path)
        ..execute(_golden(13))
        ..userVersion = 13
        ..execute('''
INSERT INTO project (id, github_repo_id, remote, default_base_branch,
  full_name) VALUES
  ('prj_1', 1, 'r', 'main', 'acme/shop'),
  ('prj_2', 2, 'r', 'main', ''),
  ('prj_3', 3, 'r', 'main', 'acme/shop');
INSERT INTO app (id, project_id, path, framework, store_country) VALUES
  ('app_1', 'prj_1', '.', 'flutter', 'us'),
  ('app_2', 'prj_1', 'apps/admin', 'flutter', 'us'),
  ('app_3', 'prj_2', '.', 'flutter', 'us'),
  ('app_4', 'prj_3', '.', 'flutter', 'us');
INSERT INTO flavor (id, app_id, name, entrypoint) VALUES
  ('flv_1', 'app_1', 'prod', 'lib/main.dart'),
  ('flv_2', 'app_1', 'dev', 'lib/main.dart'),
  ('flv_3', 'app_2', 'prod', 'lib/main.dart'),
  ('flv_4', 'app_3', 'default', 'lib/main.dart'),
  ('flv_5', 'app_4', 'prod', 'lib/main.dart');
INSERT INTO credential_ref (id, flavor_id, kind, secret_key, verified_at,
  account, status, checked_at, message, fix) VALUES
  ('crd_0000000000000001', 'flv_1', 'asc_key', 'credential.crd_0000000000000001',
    1000, 'ABC123DEF4', 'verified', 1000, NULL, NULL),
  ('crd_0000000000000002', 'flv_2', 'asc_key', 'credential.crd_0000000000000002',
    NULL, 'ABC123DEF4', 'rejected', 2000, 'Revoked.', 'Make a new one.'),
  ('crd_0000000000000003', 'flv_3', 'slack', 'credential.crd_0000000000000003',
    NULL, NULL, 'unverified', NULL, NULL, NULL),
  ('crd_0000000000000004', 'flv_4', 'keystore', 'credential.crd_0000000000000004',
    NULL, 'upload', 'unreachable', 3000, 'No keytool.', NULL),
  ('crd_0000000000000005', 'flv_1', 'github', 'github.token',
    NULL, 'octocat', 'verified', 1000, NULL, NULL),
  ('crd_0000000000000006', 'flv_2', 'github', 'github.token',
    NULL, 'octocat', 'verified', 1000, NULL, NULL),
  ('crd_0000000000000007', 'flv_5', 'asc_key', 'credential.crd_0000000000000007',
    NULL, 'XYZ', 'verified', 1000, NULL, NULL);
''')
        ..close();
      final notes = <String>[];
      final database = SqliteDatabase.open(path, onNote: notes.add);
      return (database: database, notes: notes);
    }

    test('names every credential, assigns it and drops GitHub refs', () async {
      final path = '${tempDirectory().path}/xpath.db';
      final (:database, :notes) = migrate(path);
      addTearDown(database.close);

      expect(database.connection.userVersion, latest);
      expect(File('$path.bak-v13').existsSync(), isTrue);
      final credentials = database.connection.select(
        'SELECT id, name, kind, secret_key, account, status, verified_at, '
        'checked_at, message, fix FROM credential ORDER BY id',
      );
      expect(
        [for (final row in credentials) row['name']],
        [
          'App Store Connect API key · acme/shop prod (crd_0000000000000001)',
          'App Store Connect API key · acme/shop dev',
          'Slack webhook · acme/shop apps/admin prod',
          'Android keystore · prj_2 default',
          'App Store Connect API key · acme/shop prod (crd_0000000000000007)',
        ],
      );
      expect(
        credentials.first['secret_key'],
        'credential.crd_0000000000000001',
      );
      expect(credentials.first['account'], 'ABC123DEF4');
      expect(credentials.first['verified_at'], 1000);
      expect(credentials[1]['status'], 'rejected');
      expect(credentials[1]['message'], 'Revoked.');
      expect(credentials[1]['fix'], 'Make a new one.');
      expect(credentials[3]['status'], 'unreachable');

      final assignments = database.connection.select(
        'SELECT flavor_id, kind, credential_id, status, checked_at, message '
        'FROM credential_assignment ORDER BY flavor_id',
      );
      expect(
        [
          for (final row in assignments)
            [
              for (final column in [
                'flavor_id',
                'kind',
                'credential_id',
                'status',
                'checked_at',
                'message',
              ])
                row[column],
            ].join(' '),
        ],
        [
          'flv_1 asc_key crd_0000000000000001 verified 1000 null',
          'flv_2 asc_key crd_0000000000000002 rejected 2000 null',
          'flv_3 slack crd_0000000000000003 unverified null null',
          'flv_4 keystore crd_0000000000000004 unreachable 3000 null',
          'flv_5 asc_key crd_0000000000000007 verified 1000 null',
        ],
      );
      expect(
        database.connection.select(
          "SELECT name FROM sqlite_schema WHERE name = 'credential_ref'",
        ),
        isEmpty,
      );
      const named =
          'Named 5 credential(s) after their flavor and assigned each to it '
          '(ADR 0013).';
      const dropped =
          'Dropped 2 per-flavor GitHub credential reference(s): each named the '
          "engine's GitHub token (github.token), which stays the one GitHub "
          'token of the engine.';
      expect(notes, [named, dropped]);

      final repository = SqliteCredentialRepository(database);
      final assigned = await repository.assignment(
        'flv_1',
        CredentialKind.ascKey,
      );
      expect(assigned!.flavor.projectName, 'acme/shop');
      expect(assigned.credential.check.status, CredentialStatus.verified);
      expect(
        (await repository.assignments(projectId: 'prj_2')).single.kind,
        CredentialKind.keystore,
      );
    });

    test('says nothing about an engine without credentials', () {
      final path = '${tempDirectory().path}/xpath.db';
      sqlite3.open(path)
        ..execute(_golden(13))
        ..userVersion = 13
        ..close();
      final notes = <String>[];

      SqliteDatabase.open(path, onNote: notes.add).close();

      expect(notes, isEmpty);
    });

    test('keeps a credential of one kind to flavors of that kind', () {
      final database = SqliteDatabase.openInMemory();
      addTearDown(database.close);
      database.connection.execute('''
INSERT INTO project (id, host, source_key, github_repo_id, remote,
  default_base_branch) VALUES ('prj_1', 'github.com', '1', 1, 'r', 'main');
INSERT INTO app (id, project_id, path, framework, store_country)
  VALUES ('app_1', 'prj_1', '.', 'flutter', 'us');
INSERT INTO flavor (id, app_id, name, entrypoint)
  VALUES ('flv_1', 'app_1', 'prod', 'lib/main.dart');
INSERT INTO credential (id, name, kind, secret_key)
  VALUES ('crd_1', 'Key', 'asc_key', 'k');
''');

      expect(
        () => database.connection.execute(
          'INSERT INTO credential_assignment (flavor_id, kind, credential_id) '
          "VALUES ('flv_1', 'play_sa', 'crd_1')",
        ),
        throwsA(isA<SqliteException>()),
      );
      expect(
        () => database.connection.execute(
          'INSERT INTO credential (id, name, kind, secret_key) '
          "VALUES ('crd_2', 'KEY', 'slack', 'k')",
        ),
        throwsA(isA<SqliteException>()),
        reason: 'names are unique regardless of case',
      );
      expect(
        () => database.connection.execute(
          'INSERT INTO credential (id, name, kind, secret_key) '
          "VALUES ('crd_3', 'GitHub', 'github', 'github.token')",
        ),
        throwsA(isA<SqliteException>()),
      );
    });
  });

  group('v16 projects on any git host', () {
    test('rebuilds project and keeps every row and foreign key', () async {
      final path = '${tempDirectory().path}/xpath.db';
      sqlite3.open(path)
        ..execute(_golden(15))
        ..userVersion = 15
        ..execute('''
INSERT INTO project (id, github_repo_id, remote, default_base_branch,
  release_model, gates, full_name, local_path, github_default_branch, scan,
  findings, scanned_at, edits) VALUES
  ('prj_1', 101, 'https://github.com/acme/shop.git', 'main', '{"a":1}',
    '{"b":2}', 'acme/shop', '/work/shop', 'main', '{"apps":[]}', '[]', 7,
    '{}'),
  ('prj_2', 202, 'https://github.com/acme/admin.git', 'dev', '{}', '{}',
    'acme/admin', NULL, 'dev', '{}', '[]', 0, '{}');
INSERT INTO app (id, project_id, path, framework, store_country) VALUES
  ('app_1', 'prj_1', '.', 'flutter', 'us'),
  ('app_2', 'prj_2', '.', 'flutter', 'us');
INSERT INTO flavor (id, app_id, name, entrypoint) VALUES
  ('flv_1', 'app_1', 'prod', 'lib/main.dart');
INSERT INTO workflow (id, project_id, name) VALUES ('wf_1', 'prj_1', 'ship');
INSERT INTO workflow_version (id, workflow_id, version, yaml)
  VALUES ('wv_1', 'wf_1', 1, 'jobs: {}');
INSERT INTO release (id, app_id, version, build, state)
  VALUES ('rel_1', 'app_1', '1.0.0', 1, 'draft');
INSERT INTO run (id, project_id, workflow_id, workflow_version_id, sha,
  created_at) VALUES ('run_1', 'prj_1', 'wf_1', 'wv_1', 'abc', 1);
INSERT INTO job (id, workflow_version_id, project_id, release_id, state,
  run_id) VALUES ('job_1', 'wv_1', 'prj_1', 'rel_1', 'done', 'run_1');
INSERT INTO approval (id, project_id, action, state, run_id, job_id)
  VALUES ('apr_1', 'prj_1', 'promote', 'pending', 'run_1', 'job_1');
''')
        ..close();

      final database = SqliteDatabase.open(path);
      addTearDown(database.close);
      final db = database.connection;

      expect(db.userVersion, latest);
      expect(File('$path.bak-v15').existsSync(), isTrue);
      expect(
        [
          for (final row in db.select(
            'SELECT id, host, source_key, github_repo_id, remote, '
            'default_base_branch, release_model, gates, full_name, '
            'local_path, github_default_branch, scan, scanned_at '
            'FROM project ORDER BY rowid',
          ))
            row.values,
        ],
        [
          [
            'prj_1',
            'github.com',
            '101',
            101,
            'https://github.com/acme/shop.git',
            'main',
            '{"a":1}',
            '{"b":2}',
            'acme/shop',
            '/work/shop',
            'main',
            '{"apps":[]}',
            7,
          ],
          [
            'prj_2',
            'github.com',
            '202',
            202,
            'https://github.com/acme/admin.git',
            'dev',
            '{}',
            '{}',
            'acme/admin',
            null,
            'dev',
            '{}',
            0,
          ],
        ],
      );
      for (final (table, rows) in [
        ('app', 2),
        ('flavor', 1),
        ('workflow', 1),
        ('workflow_version', 1),
        ('release', 1),
        ('run', 1),
        ('job', 1),
        ('approval', 1),
      ]) {
        expect(
          db.select('SELECT count(*) FROM $table').single.columnAt(0),
          rows,
          reason: table,
        );
      }
      expect(db.select('PRAGMA foreign_key_check'), isEmpty);
      expect(db.select('PRAGMA foreign_keys').single.columnAt(0), 1);

      db.execute("DELETE FROM project WHERE id = 'prj_2'");
      expect(
        db
            .select("SELECT count(*) FROM app WHERE project_id = 'prj_2'")
            .single
            .columnAt(0),
        0,
        reason: 'the cascade from project still works after the rebuild',
      );
      expect(
        () => db.execute("DELETE FROM project WHERE id = 'prj_1'"),
        throwsA(isA<SqliteException>()),
        reason: 'history still holds on to its project',
      );

      final record = await SqliteProjectRepository(database).get('prj_1');
      expect(record!.sourceKey, '101');
      expect(record.isOnGitHub, isTrue);
    });

    test('refuses a GitHub id off github.com, none on it, and no host', () {
      final database = SqliteDatabase.openInMemory();
      addTearDown(database.close);
      final db = database.connection
        ..execute(
          'INSERT INTO project (id, host, source_key, remote, '
          "default_base_branch) VALUES ('prj_1', 'local', 'h0123456789abcdef', "
          "'file:///srv/app.git', 'main')",
        );
      for (final (host, key, repoId) in [
        ('github.com', '9', null),
        ('bitbucket.org', 'h1123456789abcdef', 9),
        ('local', 'h0123456789abcdef', null),
        ('', 'h2123456789abcdef', null),
      ]) {
        expect(
          () => db.execute(
            'INSERT INTO project (id, host, source_key, github_repo_id, '
            "remote, default_base_branch) VALUES ('prj_x', ?, ?, ?, 'r', 'm')",
            [host, key, repoId],
          ),
          throwsA(isA<SqliteException>()),
          reason: '$host $key $repoId',
        );
      }
    });
  });

  test('v17 gives the jobs of before no narrowing', () {
    final path = '${tempDirectory().path}/xpath.db';
    sqlite3.open(path)
      ..execute(_golden(16))
      ..userVersion = 16
      ..execute('''
INSERT INTO project (id, host, source_key, github_repo_id, remote,
  default_base_branch) VALUES ('prj_1', 'github.com', '1', 1, 'r', 'main');
INSERT INTO workflow (id, project_id, name) VALUES ('wf_1', 'prj_1', 'w');
INSERT INTO workflow_version (id, workflow_id, version, yaml)
  VALUES ('wfv_1', 'wf_1', 1, '');
INSERT INTO job (id, workflow_version_id, project_id, state)
  VALUES ('job_1', 'wfv_1', 'prj_1', 'succeeded');
''')
      ..close();

    final database = SqliteDatabase.open(path);
    addTearDown(database.close);

    expect(database.connection.userVersion, latest);
    expect(
      database.connection
          .select("SELECT narrowing FROM job WHERE id = 'job_1'")
          .single['narrowing'],
      '[]',
    );
  });

  test('v22 rebuilds credential, keeps its rows and assignments, and takes '
      'dart-define files', () {
    final path = '${tempDirectory().path}/xpath.db';
    sqlite3.open(path)
      ..execute(_golden(21))
      ..userVersion = 21
      ..execute('''
INSERT INTO project (id, host, source_key, github_repo_id, remote,
  default_base_branch) VALUES ('prj_1', 'github.com', '1', 1, 'r', 'main');
INSERT INTO app (id, project_id, path, framework, store_country)
  VALUES ('app_1', 'prj_1', '.', 'flutter', 'us');
INSERT INTO flavor (id, app_id, name, entrypoint)
  VALUES ('flv_1', 'app_1', 'prod', 'lib/main.dart');
INSERT INTO credential (id, name, kind, secret_key, account, status,
  verified_at, checked_at, message, fix) VALUES
  ('crd_1', 'Keys', 'keystore', 'credential.crd_1', 'upload', 'rejected', 5, 6,
   'gone', 'replace it');
INSERT INTO credential_assignment (flavor_id, kind, credential_id)
  VALUES ('flv_1', 'keystore', 'crd_1');
''')
      ..close();

    SqliteDatabase.open(path).close();
    final db = sqlite3.open(path);
    addTearDown(db.close);

    expect(
      db
          .select(
            'SELECT id, name, kind, secret_key, account, status, verified_at, '
            'checked_at, message, fix FROM credential',
          )
          .single
          .values,
      [
        'crd_1',
        'Keys',
        'keystore',
        'credential.crd_1',
        'upload',
        'rejected',
        5,
        6,
        'gone',
        'replace it',
      ],
    );
    expect(
      db
          .select('SELECT credential_id FROM credential_assignment')
          .single
          .columnAt(0),
      'crd_1',
    );
    expect(db.select('PRAGMA foreign_key_check'), isEmpty);
    db
      ..execute(
        'INSERT INTO credential (id, name, kind, secret_key) '
        "VALUES ('crd_2', 'Defines', 'dart_defines', 'k')",
      )
      ..execute(
        'INSERT INTO credential_assignment (flavor_id, kind, credential_id) '
        "VALUES ('flv_1', 'dart_defines', 'crd_2')",
      );
    expect(
      () => db.execute(
        'INSERT INTO credential (id, name, kind, secret_key) '
        "VALUES ('crd_4', 'DEFINES', 'slack', 'k')",
      ),
      throwsA(isA<SqliteException>()),
      reason: 'names are still unique regardless of case',
    );
    expect(
      () => db.execute(
        'INSERT INTO credential (id, name, kind, secret_key) '
        "VALUES ('crd_3', 'Other', 'nope', 'k')",
      ),
      throwsA(isA<SqliteException>()),
      reason: 'the kind is still checked',
    );
  });

  test('v20 rebuilds credential, keeps its rows and assignments, and takes '
      'Apple Distribution identities', () {
    final path = '${tempDirectory().path}/xpath.db';
    sqlite3.open(path)
      ..execute(_golden(19))
      ..userVersion = 19
      ..execute('''
INSERT INTO project (id, host, source_key, github_repo_id, remote,
  default_base_branch) VALUES ('prj_1', 'github.com', '1', 1, 'r', 'main');
INSERT INTO app (id, project_id, path, framework, store_country)
  VALUES ('app_1', 'prj_1', '.', 'flutter', 'us');
INSERT INTO flavor (id, app_id, name, entrypoint)
  VALUES ('flv_1', 'app_1', 'prod', 'lib/main.dart');
INSERT INTO credential (id, name, kind, secret_key, account, status,
  verified_at, checked_at, message, fix) VALUES
  ('crd_1', 'ASC', 'asc_key', 'credential.crd_1', 'KEY1', 'verified', 5, 6,
    NULL, NULL),
  ('crd_2', 'Slack', 'slack', 'credential.crd_2', NULL, 'rejected', NULL, 7,
    'gone', 'replace it');
INSERT INTO credential_assignment (flavor_id, kind, credential_id, status)
  VALUES ('flv_1', 'asc_key', 'crd_1', 'verified');
''')
      ..close();

    final database = SqliteDatabase.open(path);
    addTearDown(database.close);
    final db = database.connection;

    expect(db.userVersion, latest);
    expect(
      [
        for (final row in db.select(
          'SELECT id, name, kind, secret_key, account, status, verified_at, '
          'checked_at, message, fix FROM credential ORDER BY rowid',
        ))
          row.values,
      ],
      [
        [
          'crd_1',
          'ASC',
          'asc_key',
          'credential.crd_1',
          'KEY1',
          'verified',
          5,
          6,
          null,
          null,
        ],
        [
          'crd_2',
          'Slack',
          'slack',
          'credential.crd_2',
          null,
          'rejected',
          null,
          7,
          'gone',
          'replace it',
        ],
      ],
    );
    expect(db.select('PRAGMA foreign_key_check'), isEmpty);
    db.execute(
      'INSERT INTO credential (id, name, kind, secret_key) '
      "VALUES ('crd_3', 'Identity', 'apple_distribution', 'k')",
    );
    expect(
      () => db.execute(
        'INSERT INTO credential (id, name, kind, secret_key) '
        "VALUES ('crd_4', 'asc', 'nope', 'k')",
      ),
      throwsA(isA<SqliteException>()),
      reason: 'the kind is still checked',
    );
    expect(
      () => db.execute(
        'INSERT INTO credential (id, name, kind, secret_key) '
        "VALUES ('crd_5', 'IDENTITY', 'slack', 'k')",
      ),
      throwsA(isA<SqliteException>()),
      reason: 'names are still unique regardless of case',
    );
    db.execute("DELETE FROM credential WHERE id = 'crd_1'");
    expect(
      db
          .select('SELECT count(*) FROM credential_assignment')
          .single
          .columnAt(0),
      0,
      reason: 'the cascade to the assignments still works',
    );
  });

  group('snapshot', () {
    for (var version = 1; version <= latest; version++) {
      test('v$version is what the first $version migration(s) build', () {
        final database = SqliteDatabase.openInMemory(
          migrations: engineMigrations.take(version).toList(),
        );
        addTearDown(database.close);

        expect(dumpSchema(database.connection), _golden(version));
        expect(database.connection.userVersion, version);
      });
    }

    test('migrating from an empty database reaches the latest golden', () {
      final directory = tempDirectory();

      final database = SqliteDatabase.open('${directory.path}/xpath.db');
      addTearDown(database.close);

      expect(dumpSchema(database.connection), _golden(latest));
      expect(database.connection.userVersion, latest);
    });

    for (var version = 1; version <= latest; version++) {
      test(
        'migrating from the v$version snapshot reaches the latest golden',
        () {
          final path = '${tempDirectory().path}/xpath.db';
          sqlite3.open(path)
            ..execute(_golden(version))
            ..userVersion = version
            ..close();

          final database = SqliteDatabase.open(path);
          addTearDown(database.close);

          expect(dumpSchema(database.connection), _golden(latest));
          expect(database.connection.userVersion, latest);
          expect(
            File('$path.bak-v$version').existsSync(),
            version < latest,
            reason: 'only a database that is migrated is backed up',
          );
        },
      );
    }
  });
}

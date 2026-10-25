import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';

import '../../helpers/schema_dump.dart';

const _v1 = Migration(
  version: 1,
  sql: 'CREATE TABLE note (id INTEGER PRIMARY KEY, body TEXT NOT NULL);',
);
const _v2 = Migration(
  version: 2,
  sql: 'ALTER TABLE note ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0;',
);

const _owners = Migration(
  version: 1,
  sql: '''
CREATE TABLE owner (id INTEGER PRIMARY KEY, name TEXT NOT NULL);
CREATE TABLE pet (
  id INTEGER PRIMARY KEY,
  owner_id INTEGER NOT NULL REFERENCES owner (id) ON DELETE CASCADE
);
''',
);

/// Rebuilds `owner` with a nullable `name`, as SQLite's 12-step procedure
/// does. With foreign keys on, dropping the old table would delete every pet.
const _rebuildOwners = Migration(
  version: 2,
  foreignKeysOff: true,
  sql: '''
CREATE TABLE new_owner (id INTEGER PRIMARY KEY, name TEXT);
INSERT INTO new_owner (id, name) SELECT id, name FROM owner;
DROP TABLE owner;
ALTER TABLE new_owner RENAME TO owner;
''',
);

Object? _pragma(SqliteDatabase database, String name) =>
    database.connection.select('PRAGMA $name').single.columnAt(0);

void main() {
  late String path;

  setUp(() => path = '${tempDirectory().path}/xpath.db');

  group('open', () {
    test('creates the database at the latest schema', () {
      final database = SqliteDatabase.open(path);
      addTearDown(database.close);

      expect(File(path).existsSync(), isTrue);
      expect(database.connection.userVersion, engineMigrations.length);
    });

    test('sets WAL, the busy timeout and foreign keys on the connection', () {
      final database = SqliteDatabase.open(
        path,
        busyTimeout: const Duration(seconds: 3),
      );
      addTearDown(database.close);

      expect(_pragma(database, 'journal_mode'), 'wal');
      expect(_pragma(database, 'busy_timeout'), 3000);
      expect(_pragma(database, 'foreign_keys'), 1);
    });

    test('waits five seconds for a lock by default', () {
      final database = SqliteDatabase.open(path);
      addTearDown(database.close);

      expect(_pragma(database, 'busy_timeout'), 5000);
    });

    test('reopening a current database backs up nothing', () {
      SqliteDatabase.open(path).close();

      final database = SqliteDatabase.open(path);
      addTearDown(database.close);

      expect(database.connection.userVersion, engineMigrations.length);
      final backups = File(path).parent
          .listSync()
          .where((entity) => entity.path.contains('.bak'));
      expect(backups, isEmpty);
    });

    test('reports a file that cannot be opened', () {
      expect(
        () => SqliteDatabase.open('${File(path).parent.path}/missing/x.db'),
        throwsA(
          isA<DatabaseOpenException>().having(
            (e) => e.toString(),
            'message',
            allOf(startsWith('Cannot open the database '), contains('missing')),
          ),
        ),
      );
    });

    test('reports a file that is not a database', () {
      File(path).writeAsStringSync('this is not sqlite, not even close' * 20);

      expect(
        () => SqliteDatabase.open(path),
        throwsA(isA<DatabaseOpenException>()),
      );
    });

    test('refuses a database written by a newer engine and leaves it', () {
      SqliteDatabase.open(path, migrations: [_v1, _v2]).close();

      expect(
        () => SqliteDatabase.open(path, migrations: [_v1]),
        throwsA(
          isA<DatabaseOpenException>().having(
            (e) => e.message,
            'message',
            allOf(contains('schema version 2'), contains('newer than the 1')),
          ),
        ),
      );
      expect(sqlite3.open(path).userVersion, 2);
      expect(File('$path.bak-v2').existsSync(), isFalse);
    });

    test('rejects migrations that do not count up from 1', () {
      expect(
        () => SqliteDatabase.openInMemory(migrations: [_v2]),
        throwsArgumentError,
      );
      expect(
        () => SqliteDatabase.openInMemory(migrations: [_v1, _v1]),
        throwsArgumentError,
      );
    });

    test('opens without migrations as an empty version 0 database', () {
      final database = SqliteDatabase.openInMemory(migrations: const []);
      addTearDown(database.close);

      expect(database.connection.userVersion, 0);
    });

    test('is readable by a second connection while the first is open', () {
      final first = SqliteDatabase.open(path);
      addTearDown(first.close);
      first.connection.execute(
        "INSERT INTO runner (id, name) VALUES ('r1', 'mini')",
      );

      final second = SqliteDatabase.open(path);
      addTearDown(second.close);

      expect(
        second.connection.select('SELECT id FROM runner').single['id'],
        'r1',
      );
    });
  });

  group('migrating', () {
    test('applies every pending migration in order', () {
      final database = SqliteDatabase.open(path, migrations: [_v1, _v2]);
      addTearDown(database.close);

      expect(database.connection.userVersion, 2);
      expect(
        database.connection
            .select('PRAGMA table_info(note)')
            .map((column) => column['name']),
        ['id', 'body', 'pinned'],
      );
    });

    test('upgrades a populated old database and keeps its rows', () {
      SqliteDatabase.open(path, migrations: [_v1])
        ..connection.execute("INSERT INTO note (body) VALUES ('keep me')")
        ..close();

      final database = SqliteDatabase.open(path, migrations: [_v1, _v2]);
      addTearDown(database.close);

      final note = database.connection.select('SELECT * FROM note').single;
      expect(note['body'], 'keep me');
      expect(note['pinned'], 0);
      expect(database.connection.userVersion, 2);
    });

    test('backs up an existing database before changing it', () {
      SqliteDatabase.open(path, migrations: [_v1])
        ..connection.execute("INSERT INTO note (body) VALUES ('before')")
        ..close();

      SqliteDatabase.open(path, migrations: [_v1, _v2]).close();

      final backup = sqlite3.open('$path.bak-v1');
      addTearDown(backup.close);
      expect(backup.userVersion, 1);
      expect(backup.select('SELECT body FROM note').single['body'], 'before');
      expect(backup.select('PRAGMA table_info(note)').map((c) => c['name']), [
        'id',
        'body',
      ], reason: 'the backup has the old schema');
    });

    test('replaces an older backup of the same version', () {
      File('$path.bak-v1').writeAsStringSync('stale');
      SqliteDatabase.open(path, migrations: [_v1]).close();

      SqliteDatabase.open(path, migrations: [_v1, _v2]).close();

      final backup = sqlite3.open('$path.bak-v1');
      addTearDown(backup.close);
      expect(backup.userVersion, 1);
    });

    test('does not back up a new database', () {
      SqliteDatabase.open(path, migrations: [_v1, _v2]).close();

      expect(File('$path.bak-v0').existsSync(), isFalse);
      expect(File('$path.bak-v1').existsSync(), isFalse);
    });

    test('backs up an unversioned database that already has tables', () {
      sqlite3.open(path)
        ..execute('CREATE TABLE legacy (id INTEGER)')
        ..close();

      expect(
        () => SqliteDatabase.open(path, migrations: [_v1]),
        returnsNormally,
      );
      expect(File('$path.bak-v0').existsSync(), isTrue);
    });

    test('rolls a failing migration back and keeps the old version', () {
      const broken = Migration(
        version: 2,
        sql:
            'CREATE TABLE half (id INTEGER); '
            'INSERT INTO table_that_is_not_there VALUES (1);',
      );
      SqliteDatabase.open(path, migrations: [_v1]).close();

      expect(
        () => SqliteDatabase.open(path, migrations: [_v1, broken]),
        throwsA(isA<DatabaseOpenException>()),
      );

      final database = SqliteDatabase.open(path, migrations: [_v1]);
      addTearDown(database.close);
      expect(database.connection.userVersion, 1);
      expect(
        database.connection.select(
          "SELECT name FROM sqlite_schema WHERE name = 'half'",
        ),
        isEmpty,
        reason: 'the half-applied migration was rolled back',
      );
      expect(File('$path.bak-v1').existsSync(), isTrue);
    });

    test('runs a migration with foreign keys off and turns them on', () {
      SqliteDatabase.open(path, migrations: [_owners])
        ..connection.execute(
          "INSERT INTO owner (id, name) VALUES (1, 'ada'); "
          'INSERT INTO pet (id, owner_id) VALUES (1, 1), (2, 1);',
        )
        ..close();

      final database = SqliteDatabase.open(
        path,
        migrations: [_owners, _rebuildOwners],
      );
      addTearDown(database.close);

      expect(database.connection.userVersion, 2);
      expect(
        database.connection.select('SELECT owner_id FROM pet ORDER BY id'),
        [
          {'owner_id': 1},
          {'owner_id': 1},
        ],
        reason: 'the rebuild kept the rows that refer to the table',
      );
      expect(_pragma(database, 'foreign_keys'), 1);
      expect(
        () => database.connection.execute(
          'INSERT INTO pet (id, owner_id) VALUES (3, 9)',
        ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('fails a migration that leaves a row referring to nothing', () {
      const orphan = Migration(
        version: 2,
        foreignKeysOff: true,
        sql: 'DELETE FROM owner WHERE id = 1;',
      );
      SqliteDatabase.open(path, migrations: [_owners])
        ..connection.execute(
          "INSERT INTO owner (id, name) VALUES (1, 'ada'); "
          'INSERT INTO pet (id, owner_id) VALUES (1, 1);',
        )
        ..close();

      expect(
        () => SqliteDatabase.open(path, migrations: [_owners, orphan]),
        throwsA(
          isA<DatabaseOpenException>().having(
            (error) => error.message,
            'message',
            'Migration 2 left 1 row(s) that refer to nothing in pet.',
          ),
        ),
      );

      final database = SqliteDatabase.open(path, migrations: [_owners]);
      addTearDown(database.close);
      expect(database.connection.userVersion, 1);
      expect(
        database.connection.select('SELECT name FROM owner').single['name'],
        'ada',
        reason: 'the migration was rolled back',
      );
    });

    test('a snapshot of an old version migrates to the fresh schema', () {
      final old = SqliteDatabase.openInMemory(migrations: [_v1]);
      addTearDown(old.close);
      sqlite3.open(path)
        ..execute(dumpSchema(old.connection))
        ..userVersion = 1
        ..close();
      final fresh = SqliteDatabase.openInMemory(migrations: [_v1, _v2]);
      addTearDown(fresh.close);

      final migrated = SqliteDatabase.open(path, migrations: [_v1, _v2]);
      addTearDown(migrated.close);

      expect(dumpSchema(migrated.connection), dumpSchema(fresh.connection));
    });
  });

  group('transaction', () {
    late SqliteDatabase database;

    setUp(() {
      database = SqliteDatabase.openInMemory(migrations: [_v1]);
      addTearDown(database.close);
    });

    int count() =>
        database.connection
                .select('SELECT count(*) FROM note')
                .single
                .columnAt(0)
            as int;

    test('commits what the action wrote and returns its result', () {
      final result = database.transaction(() {
        database.connection.execute("INSERT INTO note (body) VALUES ('a')");
        return 'done';
      });

      expect(result, 'done');
      expect(count(), 1);
    });

    test('rolls back and rethrows when the action throws', () {
      expect(
        () => database.transaction(() {
          database.connection.execute("INSERT INTO note (body) VALUES ('a')");
          throw StateError('boom');
        }),
        throwsStateError,
      );

      expect(count(), 0);
    });
  });
}

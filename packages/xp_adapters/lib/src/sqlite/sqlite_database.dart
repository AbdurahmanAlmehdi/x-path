import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:xp_adapters/src/sqlite/migration.dart';
import 'package:xp_adapters/src/sqlite/migrations.dart';

/// The database cannot be opened, or brought to the schema this engine needs.
class DatabaseOpenException implements IOException {
  /// Creates the exception with a [message] that says what is wrong.
  const new(this.message);

  /// What is wrong.
  final String message;

  @override
  String toString() => message;
}

/// The engine database: one SQLite file, one connection.
///
/// All of a process's reads and writes go through [connection], so there is a
/// single writer (ADR 0002). The API is synchronous. Other processes, such as
/// `xpd token create` while `xpd serve` runs, open the file themselves; WAL
/// lets them read while one writes, and `busy_timeout` makes a second writer
/// wait instead of failing.
class SqliteDatabase {
  new _(this.connection);

  /// Opens the database at [path], creating it if needed, and migrates it to
  /// the newest schema in [migrations].
  ///
  /// The connection uses `journal_mode=WAL`, `busy_timeout` of [busyTimeout]
  /// and `foreign_keys=ON`. When an existing database has to be migrated, a
  /// copy of it is first written to `<path>.bak-v<old version>`. [onNote]
  /// hears what a migration says it does to the data that is there
  /// ([Migration.notes]).
  ///
  /// Throws a [DatabaseOpenException] if the file cannot be opened, was
  /// written by a newer engine or a migration fails, and an [ArgumentError]
  /// if [migrations] do not count up from 1.
  static SqliteDatabase open(
    String path, {
    Duration busyTimeout = const Duration(seconds: 5),
    List<Migration> migrations = engineMigrations,
    void Function(String note)? onNote,
  }) => _open(
    () => sqlite3.open(path),
    path: path,
    busyTimeout: busyTimeout,
    migrations: migrations,
    onNote: onNote,
  );

  /// Opens an empty database that lives in memory, migrated to the newest
  /// schema in [migrations]. For tests.
  static SqliteDatabase openInMemory({
    List<Migration> migrations = engineMigrations,
    void Function(String note)? onNote,
  }) => _open(
    sqlite3.openInMemory,
    busyTimeout: Duration.zero,
    migrations: migrations,
    onNote: onNote,
  );

  /// The one connection. Use it for statements; use [transaction] to group
  /// writes.
  final Database connection;

  /// Runs [action] in a transaction that takes the write lock at once, so
  /// that it never fails halfway because another process wrote meanwhile.
  ///
  /// Commits when [action] returns and rolls back when it throws. It does not
  /// nest.
  T transaction<T>(T Function() action) => _inTransaction(connection, action);

  /// Closes the connection. WAL files are checkpointed when the last
  /// connection closes.
  void close() => connection.close();

  static SqliteDatabase _open(
    Database Function() connect, {
    required Duration busyTimeout,
    required List<Migration> migrations,
    String? path,
    void Function(String note)? onNote,
  }) {
    for (var i = 0; i < migrations.length; i++) {
      if (migrations[i].version != i + 1) {
        throw ArgumentError.value(
          migrations[i].version,
          'migrations',
          'must count up from 1; expected version ${i + 1} at index $i',
        );
      }
    }
    Database? connection;
    try {
      connection = connect();
      _configure(connection, busyTimeout);
      _migrate(connection, migrations, path, onNote);
      return ._(connection);
    } on Object catch (error) {
      connection?.close();
      if (error is SqliteException) {
        throw DatabaseOpenException(
          'Cannot open the database${path == null ? '' : ' $path'}: $error',
        );
      }
      rethrow;
    }
  }

  static void _configure(Database connection, Duration busyTimeout) {
    // The timeout comes first so that the pragmas below wait for a lock.
    connection
      ..execute('PRAGMA busy_timeout = ${busyTimeout.inMilliseconds}')
      ..execute('PRAGMA journal_mode = WAL')
      ..execute('PRAGMA foreign_keys = ON');
  }

  static void _migrate(
    Database connection,
    List<Migration> migrations,
    String? path,
    void Function(String note)? onNote,
  ) {
    final current = connection.userVersion;
    final latest = migrations.length;
    if (current > latest) {
      throw DatabaseOpenException(
        'The database${path == null ? '' : ' $path'} has schema version '
        '$current, newer than the $latest this xpd knows. Update xpd.',
      );
    }
    if (current == latest) return;
    if (path != null && _hasSchema(connection)) {
      final backup = File('$path.bak-v$current');
      if (backup.existsSync()) backup.deleteSync();
      connection.execute('VACUUM INTO ?', [backup.path]);
    }
    for (final migration in migrations) {
      // The pragma is a no-op inside a transaction, so it is set around it.
      if (migration.foreignKeysOff) {
        connection.execute('PRAGMA foreign_keys = OFF');
      }
      try {
        _inTransaction(connection, () {
          // Another process may have migrated since we looked.
          if (connection.userVersion >= migration.version) return;
          if (migration.notes case final notes?) {
            for (final row in connection.select(notes)) {
              onNote?.call(row.columnAt(0) as String);
            }
          }
          connection.execute(migration.sql);
          if (migration.foreignKeysOff) {
            _checkForeignKeys(connection, migration);
          }
          connection.userVersion = migration.version;
        });
      } finally {
        if (migration.foreignKeysOff) {
          connection.execute('PRAGMA foreign_keys = ON');
        }
      }
    }
  }

  static void _checkForeignKeys(Database connection, Migration migration) {
    final broken = connection.select('PRAGMA foreign_key_check');
    if (broken.isEmpty) return;
    final tables = {for (final row in broken) row['table'] as String};
    throw DatabaseOpenException(
      'Migration ${migration.version} left ${broken.length} row(s) that refer '
      'to nothing in ${(tables.toList()..sort()).join(', ')}.',
    );
  }

  static bool _hasSchema(Database connection) {
    final count = connection.select('SELECT count(*) FROM sqlite_schema');
    return count.single.columnAt(0) != 0;
  }

  static T _inTransaction<T>(Database connection, T Function() action) {
    connection.execute('BEGIN IMMEDIATE');
    try {
      final result = action();
      connection.execute('COMMIT');
      return result;
    } on Object {
      connection.execute('ROLLBACK');
      rethrow;
    }
  }
}

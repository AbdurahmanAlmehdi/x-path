/// One step of the schema history, applied inside a transaction.
class Migration {
  /// Creates the migration to schema [version].
  const new({
    required this.version,
    required this.sql,
    this.notes,
    this.foreignKeysOff = false,
  });

  /// The `PRAGMA user_version` the database has after this migration.
  ///
  /// Versions start at 1 and grow by one.
  final int version;

  /// The statements that bring a database from `version - 1` to [version].
  final String sql;

  /// A `SELECT` that runs just before [sql], in the same transaction, and
  /// whose rows (one text column) say what the migration does to the data
  /// that is there, for the log. `null` for none.
  final String? notes;

  /// Whether [sql] runs with `PRAGMA foreign_keys=OFF`, as a table rebuild
  /// (SQLite's 12-step procedure) needs: dropping the old table would
  /// otherwise delete or refuse the rows that refer to it. The migration
  /// fails if `PRAGMA foreign_key_check` finds a row that refers to nothing
  /// before it commits.
  final bool foreignKeysOff;
}

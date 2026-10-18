/// One step of the schema history, applied inside a transaction.
class Migration {
  /// Creates the migration to schema [version].
  const new({required this.version, required this.sql, this.notes});

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
}

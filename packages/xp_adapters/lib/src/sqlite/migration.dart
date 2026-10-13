/// One step of the schema history, applied inside a transaction.
class Migration {
  /// Creates the migration to schema [version].
  const new({required this.version, required this.sql});

  /// The `PRAGMA user_version` the database has after this migration.
  ///
  /// Versions start at 1 and grow by one.
  final int version;

  /// The statements that bring a database from `version - 1` to [version].
  final String sql;
}

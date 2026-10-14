import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';
import 'package:xp_adapters/src/sqlite/sqlite_database.dart';
import 'package:xp_adapters/src/sqlite/timestamps.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

/// The retention settings and the time of the last pruning of logs, in the
/// `housekeeping_setting` table.
class SqliteHousekeepingRepository implements HousekeepingRepository {
  /// Creates a repository over a database.
  const new(this._database);

  final SqliteDatabase _database;

  Database get _db => _database.connection;

  static const _retention = 'retention';
  static const _lastLogPrune = 'last_log_prune';

  @override
  Future<RetentionSettings> retention() async {
    final value = _read(_retention);
    return value == null
        ? const RetentionSettings()
        : RetentionSettings.fromJson(value as Map<String, dynamic>);
  }

  @override
  Future<void> saveRetention(RetentionSettings settings) async =>
      _write(_retention, settings.toJson());

  @override
  Future<DateTime?> lastLogPrune() async {
    final value = _read(_lastLogPrune);
    return value == null ? null : fromDatabaseTime(value as int);
  }

  @override
  Future<void> saveLogPrune(DateTime at) async =>
      _write(_lastLogPrune, toDatabaseTime(at));

  Object? _read(String key) {
    final rows = _db.select(
      'SELECT value FROM housekeeping_setting WHERE key = ?',
      [key],
    );
    return rows.isEmpty ? null : jsonDecode(rows.single['value'] as String);
  }

  void _write(String key, Object value) => _db.execute(
    'INSERT INTO housekeeping_setting (key, value) VALUES (?, ?) '
    'ON CONFLICT (key) DO UPDATE SET value = excluded.value',
    [key, jsonEncode(value)],
  );
}

import 'package:sqlite3/sqlite3.dart';
import 'package:xp_adapters/src/sqlite/sqlite_database.dart';
import 'package:xp_engine/xp_engine.dart';

/// The settings of the engine itself, in the `engine_setting` table.
class SqliteEngineSettingRepository implements EngineSettingRepository {
  /// Creates a repository over a database.
  const new(this._database);

  final SqliteDatabase _database;

  Database get _db => _database.connection;

  @override
  Future<String?> read(String key) async {
    final rows = _db.select('SELECT value FROM engine_setting WHERE key = ?', [
      key,
    ]);
    return rows.isEmpty ? null : rows.single['value'] as String;
  }

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      _db.execute('DELETE FROM engine_setting WHERE key = ?', [key]);
      return;
    }
    _db.execute(
      'INSERT INTO engine_setting (key, value) VALUES (?, ?) '
      'ON CONFLICT (key) DO UPDATE SET value = excluded.value',
      [key, value],
    );
  }
}

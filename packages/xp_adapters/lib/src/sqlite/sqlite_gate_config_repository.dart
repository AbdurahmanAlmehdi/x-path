import 'dart:convert';

import 'package:xp_adapters/src/sqlite/sqlite_database.dart';
import 'package:xp_engine/xp_engine.dart';

/// The gates of projects, in the `gates` column of the `project` table.
class SqliteGateConfigRepository implements GateConfigRepository {
  /// Creates a repository over a database.
  const new(this._database);

  final SqliteDatabase _database;

  @override
  Future<GateConfig> get(String projectId) async {
    final rows = _database.connection.select(
      'SELECT gates FROM project WHERE id = ?',
      [projectId],
    );
    if (rows.isEmpty) return const GateConfig();
    return GateConfig.fromJson(
      jsonDecode(rows.single['gates'] as String) as Map<String, dynamic>,
    );
  }

  @override
  Future<void> set(String projectId, GateConfig config) async {
    _database.connection.execute('UPDATE project SET gates = ? WHERE id = ?', [
      jsonEncode(config.toJson()),
      projectId,
    ]);
  }
}

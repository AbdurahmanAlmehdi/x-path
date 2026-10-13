import 'dart:convert';

import 'package:xp_adapters/src/sqlite/sqlite_database.dart';
import 'package:xp_engine/xp_engine.dart';

/// Release models in the `project.release_model` column.
///
/// An empty column (`{}`) is the default model.
class SqliteReleaseModelRepository implements ReleaseModelRepository {
  /// Creates a repository over a database.
  const new(this._database);

  final SqliteDatabase _database;

  @override
  Future<ReleaseModel> get(String projectId) async {
    final rows = _database.connection.select(
      'SELECT release_model FROM project WHERE id = ?',
      [projectId],
    );
    if (rows.isEmpty) throw ProjectNotFoundException(projectId);
    return ReleaseModel.fromJson(
      jsonDecode(rows.single['release_model'] as String)
          as Map<String, dynamic>,
    );
  }

  @override
  Future<void> save(String projectId, ReleaseModel model) async {
    _database.connection.execute(
      'UPDATE project SET release_model = ? WHERE id = ?',
      [jsonEncode(model.toJson()), projectId],
    );
    if (_database.connection.updatedRows == 0) {
      throw ProjectNotFoundException(projectId);
    }
  }
}

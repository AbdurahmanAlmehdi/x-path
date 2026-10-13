import 'package:xp_adapters/src/sqlite/sqlite_database.dart';
import 'package:xp_engine/xp_engine.dart';

/// Build number counters in the `app.build_counter` column (D-11).
class SqliteBuildCounterRepository implements BuildCounterRepository {
  /// Creates a repository over a database.
  const new(this._database);

  final SqliteDatabase _database;

  /// One statement reads, raises and returns the counter, inside a write
  /// transaction: two processes never get the same number, and a number is
  /// never given back.
  @override
  Future<int> allocate({
    required String projectId,
    required String appPath,
    required int seed,
  }) async {
    RangeError.checkNotNegative(seed, 'seed');
    final next = _database.transaction(() {
      final rows = _database.connection.select(
        'UPDATE app SET build_counter = max(build_counter, ?) + 1 '
        'WHERE project_id = ? AND path = ? RETURNING build_counter',
        [seed, projectId, appPath],
      );
      if (rows.isEmpty) throw UnknownAppException(projectId, appPath);
      return rows.single['build_counter'] as int;
    });
    return next;
  }
}

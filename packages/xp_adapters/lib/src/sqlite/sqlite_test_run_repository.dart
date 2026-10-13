import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';
import 'package:xp_adapters/src/sqlite/sqlite_database.dart';
import 'package:xp_adapters/src/sqlite/timestamps.dart';
import 'package:xp_engine/xp_engine.dart';

/// Test runs in the `test_run` table.
///
/// The tests of a run and its diff are one JSON document in `results`, in the
/// compact form of `TestRunResults.toJson`: a passing test costs its name.
class SqliteTestRunRepository implements TestRunRepository {
  /// Creates a repository over a database.
  const new(this._database);

  final SqliteDatabase _database;

  Database get _db => _database.connection;

  static const _columns =
      'id, job_id, project_id, branch, app_path, baseline, created_at, results';

  @override
  Future<void> save(TestRunRecord run) async {
    _db.execute(
      'INSERT INTO test_run ($_columns) VALUES (?, ?, ?, ?, ?, ?, ?, ?) '
      'ON CONFLICT (job_id) DO UPDATE SET id = excluded.id, '
      'project_id = excluded.project_id, branch = excluded.branch, '
      'app_path = excluded.app_path, baseline = excluded.baseline, '
      'created_at = excluded.created_at, results = excluded.results',
      [
        run.id,
        run.jobId,
        run.projectId,
        run.branch,
        run.appPath,
        if (run.baseline) 1 else 0,
        toDatabaseTime(run.createdAt),
        jsonEncode(run.resultsJson()),
      ],
    );
  }

  @override
  Future<TestRunRecord?> forJob(String jobId) async => _one(
    _db.select('SELECT $_columns FROM test_run WHERE job_id = ?', [jobId]),
  );

  @override
  Future<TestRunRecord?> baseline({
    required String projectId,
    required String appPath,
    required String branch,
  }) async => _one(
    _db.select(
      'SELECT $_columns FROM test_run WHERE project_id = ? AND app_path = ? '
      'AND branch = ? AND baseline = 1 '
      'ORDER BY created_at DESC, rowid DESC LIMIT 1',
      [projectId, appPath, branch],
    ),
  );

  @override
  Future<List<TestRunRecord>> baselines(String projectId) async => [
    for (final row in _db.select(
      'SELECT $_columns FROM test_run AS run '
      'WHERE project_id = ? AND baseline = 1 AND NOT EXISTS '
      '(SELECT 1 FROM test_run AS newer '
      'WHERE newer.project_id = run.project_id '
      'AND newer.app_path = run.app_path AND newer.branch = run.branch '
      'AND newer.baseline = 1 AND (newer.created_at > run.created_at '
      'OR (newer.created_at = run.created_at AND newer.rowid > run.rowid))) '
      'ORDER BY app_path, branch',
      [projectId],
    ))
      _fromRow(row),
  ];

  static TestRunRecord? _one(ResultSet rows) =>
      rows.isEmpty ? null : _fromRow(rows.single);

  static TestRunRecord _fromRow(Row row) => TestRunRecord.fromStored(
    id: row['id'] as String,
    jobId: row['job_id'] as String,
    projectId: row['project_id'] as String,
    branch: row['branch'] as String,
    appPath: row['app_path'] as String,
    baseline: row['baseline'] == 1,
    createdAt: fromDatabaseTime(row['created_at'] as int),
    stored: jsonDecode(row['results'] as String) as Map<String, dynamic>,
  );
}

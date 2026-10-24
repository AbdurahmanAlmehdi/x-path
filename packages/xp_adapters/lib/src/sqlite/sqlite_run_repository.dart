import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';
import 'package:xp_adapters/src/sqlite/sqlite_database.dart';
import 'package:xp_adapters/src/sqlite/timestamps.dart';
import 'package:xp_engine/xp_engine.dart';

/// Runs in the `run` table. The jobs of a run are in `job`, which names its
/// run.
class SqliteRunRepository implements RunRepository {
  /// Creates a repository over a database.
  const new(this._database);

  final SqliteDatabase _database;

  Database get _db => _database.connection;

  @override
  Future<void> create(RunRecord run) async {
    _db.execute(
      'INSERT INTO run (id, project_id, workflow_id, workflow_version_id, '
      'sha, ref, locks_project, lock_held, version, build, request, '
      'created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        run.id,
        run.projectId,
        run.workflowId,
        run.workflowVersionId,
        run.sha,
        run.ref,
        if (run.locksProject) 1 else 0,
        if (run.lockHeld) 1 else 0,
        run.version,
        run.build,
        jsonEncode(run.request),
        toDatabaseTime(run.createdAt),
      ],
    );
  }

  static const _columns =
      'id, project_id, workflow_id, workflow_version_id, sha, ref, '
      'locks_project, lock_held, version, build, request, created_at';

  @override
  Future<RunRecord?> get(String id) async {
    final rows = _db.select('SELECT $_columns FROM run WHERE id = ?', [id]);
    return rows.isEmpty ? null : _fromRow(rows.single);
  }

  @override
  Future<List<RunRecord>> held() async => [
    for (final row in _db.select(
      'SELECT $_columns FROM run WHERE lock_held = 1 ORDER BY created_at',
    ))
      _fromRow(row),
  ];

  @override
  Future<List<RunRecord>> list({
    String? projectId,
    String? workflowId,
    String? before,
    int limit = 50,
  }) async => [
    for (final row in _db.select(
      'SELECT $_columns FROM run '
      'WHERE (?1 IS NULL OR project_id = ?1) '
      'AND (?2 IS NULL OR workflow_id = ?2) '
      'AND (?3 IS NULL OR (created_at, id) < '
      '(SELECT created_at, id FROM run WHERE id = ?3)) '
      'ORDER BY created_at DESC, id DESC LIMIT ?4',
      [projectId, workflowId, before, limit],
    ))
      _fromRow(row),
  ];

  static RunRecord _fromRow(Row row) {
    return RunRecord(
      id: row['id'] as String,
      projectId: row['project_id'] as String,
      workflowId: row['workflow_id'] as String,
      workflowVersionId: row['workflow_version_id'] as String,
      sha: row['sha'] as String,
      ref: row['ref'] as String?,
      locksProject: row['locks_project'] == 1,
      lockHeld: row['lock_held'] == 1,
      version: row['version'] as String?,
      build: row['build'] as int?,
      request: jsonDecode(row['request'] as String) as Map<String, dynamic>,
      createdAt: fromDatabaseTime(row['created_at'] as int),
    );
  }

  @override
  Future<void> setLockHeld(String id, {required bool held}) async {
    _db.execute('UPDATE run SET lock_held = ? WHERE id = ?', [
      if (held) 1 else 0,
      id,
    ]);
  }
}

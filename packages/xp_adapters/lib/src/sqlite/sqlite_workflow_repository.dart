import 'package:sqlite3/sqlite3.dart';
import 'package:xp_adapters/src/sqlite/sqlite_database.dart';
import 'package:xp_adapters/src/sqlite/timestamps.dart';
import 'package:xp_engine/xp_engine.dart';

/// Workflows and their versions in the `workflow` and `workflow_version`
/// tables.
class SqliteWorkflowRepository implements WorkflowRepository {
  /// Creates a repository over a database.
  const new(this._database);

  static const _sqliteConstraintForeignKey = 787;

  final SqliteDatabase _database;

  Database get _db => _database.connection;

  static const _versionColumns = 'id, workflow_id, version, yaml, created_at';

  @override
  Future<List<WorkflowRecord>> list(String projectId) async => [
    for (final row in _db.select(
      'SELECT id, project_id, name, builtin FROM workflow '
      'WHERE project_id = ? ORDER BY name',
      [projectId],
    ))
      _workflow(row),
  ];

  @override
  Future<WorkflowRecord?> get(String id) async => _one(
    _db.select(
      'SELECT id, project_id, name, builtin FROM workflow WHERE id = ?',
      [id],
    ),
  );

  @override
  Future<WorkflowRecord?> findByName(String projectId, String name) async =>
      _one(
        _db.select(
          'SELECT id, project_id, name, builtin FROM workflow '
          'WHERE project_id = ? AND name = ?',
          [projectId, name],
        ),
      );

  @override
  Future<void> create(
    WorkflowRecord workflow,
    WorkflowVersionRecord first,
  ) async {
    _database.transaction(() {
      _db
        ..execute(
          'INSERT INTO workflow (id, project_id, name, builtin) '
          'VALUES (?, ?, ?, ?)',
          [
            workflow.id,
            workflow.projectId,
            workflow.name,
            if (workflow.builtin) 1 else 0,
          ],
        )
        ..execute(
          'INSERT INTO workflow_version ($_versionColumns) '
          'VALUES (?, ?, ?, ?, ?)',
          [
            first.id,
            first.workflowId,
            first.version,
            first.yaml,
            toDatabaseTime(first.createdAt),
          ],
        );
    });
  }

  @override
  Future<WorkflowVersionRecord> addVersion({
    required String workflowId,
    required String versionId,
    required String yaml,
    required DateTime createdAt,
  }) async {
    final version = _database.transaction(() {
      final newest =
          _db
                  .select(
                    'SELECT max(version) FROM workflow_version '
                    'WHERE workflow_id = ?',
                    [workflowId],
                  )
                  .single
                  .columnAt(0)
              as int;
      _db.execute(
        'INSERT INTO workflow_version ($_versionColumns) '
        'VALUES (?, ?, ?, ?, ?)',
        [versionId, workflowId, newest + 1, yaml, toDatabaseTime(createdAt)],
      );
      return newest + 1;
    });
    return WorkflowVersionRecord(
      id: versionId,
      workflowId: workflowId,
      version: version,
      yaml: yaml,
      createdAt: createdAt,
    );
  }

  @override
  Future<List<WorkflowVersionRecord>> versions(String workflowId) async => [
    for (final row in _db.select(
      'SELECT $_versionColumns FROM workflow_version '
      'WHERE workflow_id = ? ORDER BY version',
      [workflowId],
    ))
      _version(row),
  ];

  @override
  Future<WorkflowVersionRecord?> versionById(String id) async {
    final rows = _db.select(
      'SELECT $_versionColumns FROM workflow_version WHERE id = ?',
      [id],
    );
    return rows.isEmpty ? null : _version(rows.single);
  }

  @override
  Future<bool> remove(String id) async {
    try {
      _db.execute('DELETE FROM workflow WHERE id = ?', [id]);
    } on SqliteException catch (error) {
      if (error.extendedResultCode == _sqliteConstraintForeignKey) {
        throw WorkflowInUseException(id);
      }
      rethrow;
    }
    return _db.updatedRows > 0;
  }

  WorkflowRecord? _one(ResultSet rows) =>
      rows.isEmpty ? null : _workflow(rows.single);

  static WorkflowRecord _workflow(Row row) => WorkflowRecord(
    id: row['id'] as String,
    projectId: row['project_id'] as String,
    name: row['name'] as String,
    builtin: row['builtin'] == 1,
  );

  static WorkflowVersionRecord _version(Row row) => WorkflowVersionRecord(
    id: row['id'] as String,
    workflowId: row['workflow_id'] as String,
    version: row['version'] as int,
    yaml: row['yaml'] as String,
    createdAt: fromDatabaseTime(row['created_at'] as int),
  );
}

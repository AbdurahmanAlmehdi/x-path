import 'package:sqlite3/sqlite3.dart';
import 'package:xp_adapters/src/sqlite/sqlite_database.dart';
import 'package:xp_adapters/src/sqlite/timestamps.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

/// Approvals in the `approval` table.
///
/// Every statement that changes a row is atomic: a decision is one `UPDATE`
/// that applies only `WHERE state = 'pending'`, and the repository checks how
/// many rows it changed, so of two concurrent decisions exactly one gets the
/// record. The connection is synchronous, so a find-then-insert (and the
/// unique index on the binding behind it) cannot interleave either.
class SqliteApprovalRepository implements ApprovalRepository {
  /// Creates a repository over a database.
  const new(this._database);

  final SqliteDatabase _database;

  Database get _db => _database.connection;

  static const _columns =
      'id, project_id, action, sha, version, run_id, job_id, state, '
      'created_at, expires_at, decided_at, decided_by, decided_by_name, '
      'decided_by_kind, reason';

  @override
  Future<ApprovalRecord?> get(String id) async => _get(id);

  ApprovalRecord? _get(String id) {
    final rows = _db.select('SELECT $_columns FROM approval WHERE id = ?', [
      id,
    ]);
    return rows.isEmpty ? null : _fromRow(rows.single);
  }

  @override
  Future<List<ApprovalRecord>> list({
    String? projectId,
    ApprovalState? state,
  }) async => [
    for (final row in _db.select(
      'SELECT $_columns FROM approval '
      'WHERE (?1 IS NULL OR project_id = ?1) AND (?2 IS NULL OR state = ?2) '
      'ORDER BY created_at DESC, rowid DESC',
      [projectId, state?.wire],
    ))
      _fromRow(row),
  ];

  @override
  Future<({ApprovalRecord record, bool created})> findOrCreate(
    ApprovalRecord candidate,
  ) async {
    final found = _database.transaction(() {
      final rows = _db.select(
        'SELECT $_columns FROM approval WHERE project_id = ? AND action = ? '
        'AND sha IS ? AND version IS ? AND run_id IS ?',
        [
          candidate.projectId,
          candidate.action.wire,
          candidate.sha,
          candidate.version,
          candidate.runId,
        ],
      );
      if (rows.isNotEmpty) {
        return (record: _fromRow(rows.single), created: false);
      }
      _db.execute(
        'INSERT INTO approval (id, project_id, action, sha, version, run_id, '
        'job_id, state, created_at, expires_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          candidate.id,
          candidate.projectId,
          candidate.action.wire,
          candidate.sha,
          candidate.version,
          candidate.runId,
          candidate.jobId,
          candidate.state.wire,
          toDatabaseTime(candidate.createdAt),
          toDatabaseTime(candidate.expiresAt),
        ],
      );
      return (record: candidate, created: true);
    });
    return found;
  }

  @override
  Future<ApprovalRecord?> decide(
    String id, {
    required ApprovalState state,
    required DecidedBy by,
    required DateTime at,
    String? reason,
  }) async {
    _db.execute(
      'UPDATE approval SET state = ?, decided_at = ?, decided_by = ?, '
      'decided_by_name = ?, decided_by_kind = ?, reason = ? '
      "WHERE id = ? AND state = 'pending' AND expires_at > ?",
      [
        state.wire,
        toDatabaseTime(at),
        by.tokenId,
        by.name,
        by.kind.name,
        reason,
        id,
        toDatabaseTime(at),
      ],
    );
    return _db.updatedRows == 0 ? null : _get(id);
  }

  @override
  Future<List<ApprovalRecord>> expireDue(
    DateTime now, {
    required String reason,
    String? id,
  }) async {
    final expired = _database.transaction(() {
      final due = [
        for (final row in _db.select(
          "SELECT id FROM approval WHERE state = 'pending' AND expires_at <= ? "
          'AND (?2 IS NULL OR id = ?2) ORDER BY created_at, rowid',
          [toDatabaseTime(now), id],
        ))
          row['id'] as String,
      ];
      for (final dueId in due) {
        _db.execute(
          "UPDATE approval SET state = 'expired', decided_at = ?, reason = ? "
          "WHERE id = ? AND state = 'pending'",
          [toDatabaseTime(now), reason, dueId],
        );
      }
      return [for (final dueId in due) _get(dueId)!];
    });
    return expired;
  }

  static ApprovalRecord _fromRow(Row row) {
    final decidedBy = row['decided_by'] as String?;
    return ApprovalRecord(
      id: row['id'] as String,
      projectId: row['project_id'] as String,
      action: GateAction.fromWire(row['action'] as String)!,
      sha: row['sha'] as String,
      version: row['version'] as String?,
      runId: row['run_id'] as String?,
      jobId: row['job_id'] as String?,
      state: ApprovalState.values.firstWhere(
        (state) => state.wire == row['state'],
      ),
      createdAt: fromDatabaseTime(row['created_at'] as int),
      expiresAt: fromDatabaseTime(row['expires_at'] as int),
      decidedAt: row['decided_at'] == null
          ? null
          : fromDatabaseTime(row['decided_at'] as int),
      decidedBy: decidedBy == null
          ? null
          : DecidedBy(
              tokenId: decidedBy,
              name: row['decided_by_name'] as String,
              kind: DeviceTokenKind.values.byName(
                row['decided_by_kind'] as String,
              ),
            ),
      reason: row['reason'] as String?,
    );
  }
}

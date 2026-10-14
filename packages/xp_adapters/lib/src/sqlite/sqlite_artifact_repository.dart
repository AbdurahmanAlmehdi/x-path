import 'package:sqlite3/sqlite3.dart';
import 'package:xp_adapters/src/sqlite/sqlite_database.dart';
import 'package:xp_adapters/src/sqlite/timestamps.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

/// Artifacts in the `artifact` table.
///
/// The kind is stored as its wire name (`shorebird_symbols`), `path` as the
/// path in the artifact store (`<job id>/<file name>`).
class SqliteArtifactRepository implements ArtifactRepository {
  /// Creates a repository over a database.
  const new(this._database);

  final SqliteDatabase _database;

  Database get _db => _database.connection;

  static const _columns =
      'id, job_id, kind, path, size, sha256, pinned, created_at';

  @override
  Future<void> save(ArtifactRecord record) async {
    _db.execute(
      'INSERT INTO artifact ($_columns) VALUES (?, ?, ?, ?, ?, ?, ?, ?) '
      'ON CONFLICT (id) DO UPDATE SET job_id = excluded.job_id, '
      'kind = excluded.kind, path = excluded.path, size = excluded.size, '
      'sha256 = excluded.sha256, pinned = excluded.pinned, '
      'created_at = excluded.created_at',
      [
        record.id,
        record.jobId,
        record.kind.wire,
        record.path,
        record.size,
        record.sha256,
        _flag(record.pinned),
        toDatabaseTime(record.createdAt),
      ],
    );
  }

  @override
  Future<ArtifactRecord?> get(String id) async =>
      _one(_db.select('SELECT $_columns FROM artifact WHERE id = ?', [id]));

  @override
  Future<ArtifactRecord?> findByPath(String jobId, String path) async => _one(
    _db.select('SELECT $_columns FROM artifact WHERE job_id = ? AND path = ?', [
      jobId,
      path,
    ]),
  );

  @override
  Future<List<ArtifactRecord>> forJob(String jobId) async => [
    for (final row in _db.select(
      'SELECT $_columns FROM artifact WHERE job_id = ? '
      'ORDER BY created_at, rowid',
      [jobId],
    ))
      _fromRow(row),
  ];

  @override
  Future<ArtifactRecord?> setPinned(String id, {required bool pinned}) async {
    _db.execute('UPDATE artifact SET pinned = ? WHERE id = ?', [
      _flag(pinned),
      id,
    ]);
    return await get(id);
  }

  @override
  Future<bool> delete(String id) async {
    _db.execute('DELETE FROM artifact WHERE id = ?', [id]);
    return _db.updatedRows > 0;
  }

  static int _flag(bool value) => value ? 1 : 0;

  static ArtifactRecord? _one(ResultSet rows) =>
      rows.isEmpty ? null : _fromRow(rows.single);

  static ArtifactRecord _fromRow(Row row) => ArtifactRecord(
    id: row['id'] as String,
    jobId: row['job_id'] as String,
    kind: ArtifactKind.values.firstWhere((kind) => kind.wire == row['kind']),
    path: row['path'] as String,
    size: row['size'] as int,
    sha256: row['sha256'] as String,
    pinned: row['pinned'] == 1,
    createdAt: fromDatabaseTime(row['created_at'] as int),
  );
}

import 'package:sqlite3/sqlite3.dart';
import 'package:xp_adapters/src/sqlite/sqlite_database.dart';
import 'package:xp_adapters/src/sqlite/timestamps.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

/// Credential references in the `credential_ref` table, with the flavor, app
/// and project they belong to.
///
/// A reference holds no secret: `secret_key` names the secret in the secret
/// store. A flavor has one reference per kind. Deleting a flavor deletes its
/// references (`ON DELETE CASCADE`); the secrets stay until the credential is
/// removed through the service.
class SqliteCredentialRepository implements CredentialRepository {
  /// Creates a repository over a database.
  const new(this._database);

  final SqliteDatabase _database;

  Database get _db => _database.connection;

  static const _select =
      'SELECT credential_ref.id, credential_ref.kind, '
      'credential_ref.secret_key, credential_ref.account, '
      'credential_ref.status, credential_ref.verified_at, '
      'credential_ref.checked_at, credential_ref.message, credential_ref.fix, '
      'flavor.id AS flavor_id, flavor.name AS flavor_name, '
      'flavor.ios_bundle_id, flavor.android_app_id, '
      'app.path AS app_path, app.project_id '
      'FROM credential_ref '
      'JOIN flavor ON flavor.id = credential_ref.flavor_id '
      'JOIN app ON app.id = flavor.app_id';

  @override
  Future<CredentialFlavor?> findFlavor(
    String projectId,
    String appPath,
    String flavorName,
  ) async {
    final rows = _db.select(
      'SELECT flavor.id, flavor.name, flavor.ios_bundle_id, '
      'flavor.android_app_id, app.path, app.project_id '
      'FROM flavor JOIN app ON app.id = flavor.app_id '
      'WHERE app.project_id = ? AND app.path = ? AND flavor.name = ?',
      [projectId, appPath, flavorName],
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    return CredentialFlavor(
      id: row['id'] as String,
      projectId: row['project_id'] as String,
      appPath: row['path'] as String,
      name: row['name'] as String,
      iosBundleId: row['ios_bundle_id'] as String?,
      androidAppId: row['android_app_id'] as String?,
    );
  }

  @override
  Future<List<CredentialRecord>> list({
    String? projectId,
    String? flavorId,
  }) async {
    final where = [
      if (flavorId != null) 'credential_ref.flavor_id = ?',
      if (projectId != null) 'app.project_id = ?',
    ];
    return [
      for (final row in _db.select(
        '$_select${where.isEmpty ? '' : ' WHERE ${where.join(' AND ')}'} '
        'ORDER BY credential_ref.rowid',
        [?flavorId, ?projectId],
      ))
        _record(row),
    ];
  }

  @override
  Future<CredentialRecord?> get(String id) async =>
      _one(_db.select('$_select WHERE credential_ref.id = ?', [id]));

  @override
  Future<CredentialRecord?> find(String flavorId, CredentialKind kind) async =>
      _one(
        _db.select(
          '$_select WHERE credential_ref.flavor_id = ? '
          'AND credential_ref.kind = ?',
          [flavorId, kind.wire],
        ),
      );

  @override
  Future<void> save(CredentialRecord record) async {
    _db.execute(
      'INSERT INTO credential_ref (id, flavor_id, kind, secret_key, account, '
      'status, verified_at, checked_at, message, fix) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?) '
      'ON CONFLICT (id) DO UPDATE SET secret_key = excluded.secret_key, '
      'account = excluded.account, status = excluded.status, '
      'verified_at = excluded.verified_at, checked_at = excluded.checked_at, '
      'message = excluded.message, fix = excluded.fix',
      [
        record.id,
        record.flavor.id,
        record.kind.wire,
        record.secretKey,
        record.account,
        record.status.wire,
        _time(record.verifiedAt),
        _time(record.checkedAt),
        record.message,
        record.fix,
      ],
    );
  }

  @override
  Future<bool> delete(String id) async {
    _db.execute('DELETE FROM credential_ref WHERE id = ?', [id]);
    return _db.updatedRows > 0;
  }

  @override
  Future<int> countUsing(String secretKey) async =>
      _db.select(
            'SELECT count(*) AS n FROM credential_ref WHERE secret_key = ?',
            [secretKey],
          ).single['n']
          as int;

  CredentialRecord? _one(ResultSet rows) =>
      rows.isEmpty ? null : _record(rows.single);

  static int? _time(DateTime? time) =>
      time == null ? null : toDatabaseTime(time);

  static DateTime? _readTime(Object? value) =>
      value is int ? fromDatabaseTime(value) : null;

  static CredentialRecord _record(Row row) => CredentialRecord(
    id: row['id'] as String,
    flavor: CredentialFlavor(
      id: row['flavor_id'] as String,
      projectId: row['project_id'] as String,
      appPath: row['app_path'] as String,
      name: row['flavor_name'] as String,
      iosBundleId: row['ios_bundle_id'] as String?,
      androidAppId: row['android_app_id'] as String?,
    ),
    kind: CredentialKind.fromWire(row['kind'] as String)!,
    secretKey: row['secret_key'] as String,
    account: row['account'] as String?,
    status: CredentialStatus.values.firstWhere(
      (status) => status.wire == row['status'],
    ),
    verifiedAt: _readTime(row['verified_at']),
    checkedAt: _readTime(row['checked_at']),
    message: row['message'] as String?,
    fix: row['fix'] as String?,
  );
}

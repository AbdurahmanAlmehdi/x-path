import 'package:sqlite3/sqlite3.dart';
import 'package:xp_adapters/src/sqlite/sqlite_database.dart';
import 'package:xp_adapters/src/sqlite/timestamps.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

/// Named credentials in the `credential` table and the flavors that use them
/// in `credential_assignment` (ADR 0013).
///
/// A credential holds no secret: `secret_key` names the secret in the secret
/// store. Names are unique regardless of case (the index uses `NOCASE`; the
/// service compares in full Unicode first). A flavor uses one credential per
/// kind, of that kind. Deleting a flavor or a credential deletes its
/// assignments (`ON DELETE CASCADE`); the secrets stay until the credential is
/// removed through the service.
class SqliteCredentialRepository implements CredentialRepository {
  /// Creates a repository over a database.
  const new(this._database);

  final SqliteDatabase _database;

  Database get _db => _database.connection;

  static const _credentialColumns =
      'credential.id, credential.name, credential.kind, '
      'credential.secret_key, credential.account, credential.status, '
      'credential.verified_at, credential.checked_at, credential.message, '
      'credential.fix';

  static const _flavorColumns =
      'flavor.id AS flavor_id, flavor.name AS flavor_name, '
      'flavor.ios_bundle_id, flavor.android_app_id, '
      'app.path AS app_path, app.project_id, project.full_name';

  static const _flavorJoin =
      'JOIN app ON app.id = flavor.app_id '
      'JOIN project ON project.id = app.project_id';

  static const _selectAssignments =
      'SELECT $_credentialColumns, $_flavorColumns, '
      'credential_assignment.status AS a_status, '
      'credential_assignment.verified_at AS a_verified_at, '
      'credential_assignment.checked_at AS a_checked_at, '
      'credential_assignment.message AS a_message, '
      'credential_assignment.fix AS a_fix '
      'FROM credential_assignment '
      'JOIN credential ON credential.id = credential_assignment.credential_id '
      'JOIN flavor ON flavor.id = credential_assignment.flavor_id '
      '$_flavorJoin';

  static const _assignmentOrder =
      'ORDER BY app.project_id, app.path, flavor.name, '
      'credential_assignment.rowid';

  @override
  Future<CredentialFlavor?> findFlavor(
    String projectId,
    String appPath,
    String flavorName,
  ) async {
    final rows = _db.select(
      'SELECT $_flavorColumns FROM flavor $_flavorJoin '
      'WHERE app.project_id = ? AND app.path = ? AND flavor.name = ?',
      [projectId, appPath, flavorName],
    );
    return rows.isEmpty ? null : _flavor(rows.single);
  }

  @override
  Future<List<CredentialFlavor>> flavorsOf(
    String projectId,
    String appPath,
  ) async => [
    for (final row in _db.select(
      'SELECT $_flavorColumns FROM flavor $_flavorJoin '
      'WHERE app.project_id = ? AND app.path = ? ORDER BY flavor.name',
      [projectId, appPath],
    ))
      _flavor(row),
  ];

  @override
  Future<List<CredentialRecord>> list() async => [
    for (final row in _db.select(
      'SELECT $_credentialColumns FROM credential '
      'ORDER BY credential.name COLLATE NOCASE, credential.id',
    ))
      _record(row),
  ];

  @override
  Future<CredentialRecord?> get(String id) async => _one(
    _db.select('SELECT $_credentialColumns FROM credential WHERE id = ?', [id]),
  );

  @override
  Future<CredentialRecord?> findByName(String name) async {
    final lower = name.toLowerCase();
    // NOCASE folds ASCII only; the comparison in Dart covers the rest.
    for (final record in await list()) {
      if (record.name.toLowerCase() == lower) return record;
    }
    return null;
  }

  @override
  Future<void> save(CredentialRecord record) async {
    final check = record.check;
    _db.execute(
      'INSERT INTO credential (id, name, kind, secret_key, account, status, '
      'verified_at, checked_at, message, fix) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?) '
      'ON CONFLICT (id) DO UPDATE SET name = excluded.name, '
      'secret_key = excluded.secret_key, account = excluded.account, '
      'status = excluded.status, verified_at = excluded.verified_at, '
      'checked_at = excluded.checked_at, message = excluded.message, '
      'fix = excluded.fix',
      [
        record.id,
        record.name,
        record.kind.wire,
        record.secretKey,
        record.account,
        check.status.wire,
        _time(check.verifiedAt),
        _time(check.checkedAt),
        check.message,
        check.fix,
      ],
    );
  }

  @override
  Future<bool> delete(String id) async {
    _db.execute('DELETE FROM credential WHERE id = ?', [id]);
    return _db.updatedRows > 0;
  }

  @override
  Future<int> countUsing(String secretKey) async =>
      _db.select('SELECT count(*) AS n FROM credential WHERE secret_key = ?', [
            secretKey,
          ]).single['n']
          as int;

  @override
  Future<List<AssignedCredential>> assignments({
    String? projectId,
    String? flavorId,
    String? credentialId,
  }) async {
    final where = [
      if (projectId != null) 'app.project_id = ?',
      if (flavorId != null) 'credential_assignment.flavor_id = ?',
      if (credentialId != null) 'credential_assignment.credential_id = ?',
    ];
    return [
      for (final row in _db.select(
        '$_selectAssignments'
        '${where.isEmpty ? '' : ' WHERE ${where.join(' AND ')}'} '
        '$_assignmentOrder',
        [?projectId, ?flavorId, ?credentialId],
      ))
        _assignment(row),
    ];
  }

  @override
  Future<AssignedCredential?> assignment(
    String flavorId,
    CredentialKind kind,
  ) async {
    final rows = _db.select(
      '$_selectAssignments WHERE credential_assignment.flavor_id = ? '
      'AND credential_assignment.kind = ?',
      [flavorId, kind.wire],
    );
    return rows.isEmpty ? null : _assignment(rows.single);
  }

  @override
  Future<void> assign(AssignedCredential assignment) async {
    final check = assignment.check;
    _db.execute(
      'INSERT INTO credential_assignment (flavor_id, kind, credential_id, '
      'status, verified_at, checked_at, message, fix) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?) '
      'ON CONFLICT (flavor_id, kind) DO UPDATE SET '
      'credential_id = excluded.credential_id, status = excluded.status, '
      'verified_at = excluded.verified_at, checked_at = excluded.checked_at, '
      'message = excluded.message, fix = excluded.fix',
      [
        assignment.flavor.id,
        assignment.kind.wire,
        assignment.id,
        check.status.wire,
        _time(check.verifiedAt),
        _time(check.checkedAt),
        check.message,
        check.fix,
      ],
    );
  }

  @override
  Future<bool> unassign(String flavorId, CredentialKind kind) async {
    _db.execute(
      'DELETE FROM credential_assignment WHERE flavor_id = ? AND kind = ?',
      [flavorId, kind.wire],
    );
    return _db.updatedRows > 0;
  }

  CredentialRecord? _one(ResultSet rows) =>
      rows.isEmpty ? null : _record(rows.single);

  static int? _time(DateTime? time) =>
      time == null ? null : toDatabaseTime(time);

  static DateTime? _readTime(Object? value) =>
      value is int ? fromDatabaseTime(value) : null;

  static CredentialStatus _status(Object? wire) =>
      CredentialStatus.values.firstWhere((status) => status.wire == wire);

  static CredentialFlavor _flavor(Row row) {
    final projectName = row['full_name'] as String?;
    return CredentialFlavor(
      id: row['flavor_id'] as String,
      projectId: row['project_id'] as String,
      projectName: projectName == null || projectName.isEmpty
          ? null
          : projectName,
      appPath: row['app_path'] as String,
      name: row['flavor_name'] as String,
      iosBundleId: row['ios_bundle_id'] as String?,
      androidAppId: row['android_app_id'] as String?,
    );
  }

  static CredentialRecord _record(Row row) => CredentialRecord(
    id: row['id'] as String,
    name: row['name'] as String,
    kind: CredentialKind.fromWire(row['kind'] as String)!,
    secretKey: row['secret_key'] as String,
    account: row['account'] as String?,
    check: CredentialCheck(
      status: _status(row['status']),
      verifiedAt: _readTime(row['verified_at']),
      checkedAt: _readTime(row['checked_at']),
      message: row['message'] as String?,
      fix: row['fix'] as String?,
    ),
  );

  static AssignedCredential _assignment(Row row) => AssignedCredential(
    flavor: _flavor(row),
    credential: _record(row),
    check: CredentialCheck(
      status: _status(row['a_status']),
      verifiedAt: _readTime(row['a_verified_at']),
      checkedAt: _readTime(row['a_checked_at']),
      message: row['a_message'] as String?,
      fix: row['a_fix'] as String?,
    ),
  );
}

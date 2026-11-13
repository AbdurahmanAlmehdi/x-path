import 'package:sqlite3/sqlite3.dart';
import 'package:xp_adapters/src/sqlite/sqlite_database.dart';
import 'package:xp_adapters/src/sqlite/timestamps.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

/// Device tokens in the `device_token` table.
///
/// Reads hit the database every time, so a token created by `xpd token create`
/// works at once in a running engine.
class SqliteDeviceTokenRepository implements DeviceTokenRepository {
  /// Creates a repository over a database.
  const new(this._database);

  final SqliteDatabase _database;

  @override
  Future<List<DeviceToken>> list() async => [
    for (final row in _database.connection.select(
      'SELECT id, name, kind, hash, person_id, created_at, revoked_at, '
      'expires_at FROM device_token ORDER BY rowid',
    ))
      _fromRow(row),
  ];

  @override
  Future<void> add(DeviceToken token) async {
    final revokedAt = token.revokedAt;
    final expiresAt = token.expiresAt;
    _database.connection.execute(
      'INSERT INTO device_token (id, name, kind, hash, person_id, created_at, '
      'revoked_at, expires_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [
        token.id,
        token.name,
        token.kind.name,
        token.hash,
        token.personId,
        toDatabaseTime(token.createdAt),
        if (revokedAt == null) null else toDatabaseTime(revokedAt),
        if (expiresAt == null) null else toDatabaseTime(expiresAt),
      ],
    );
  }

  @override
  Future<bool> revoke(String id, {required DateTime at}) async {
    _database.connection.execute(
      'UPDATE device_token SET revoked_at = ? '
      'WHERE id = ? AND revoked_at IS NULL',
      [toDatabaseTime(at), id],
    );
    return _database.connection.updatedRows > 0;
  }

  @override
  Future<int> revokeOwnedBy(String personId, {required DateTime at}) async {
    _database.connection.execute(
      'UPDATE device_token SET revoked_at = ? '
      'WHERE person_id = ? AND revoked_at IS NULL',
      [toDatabaseTime(at), personId],
    );
    return _database.connection.updatedRows;
  }

  static DeviceToken _fromRow(Row row) {
    final revokedAt = row['revoked_at'] as int?;
    final expiresAt = row['expires_at'] as int?;
    return DeviceToken(
      id: row['id'] as String,
      name: row['name'] as String,
      kind: DeviceTokenKind.values.byName(row['kind'] as String),
      hash: row['hash'] as String,
      createdAt: fromDatabaseTime(row['created_at'] as int),
      revokedAt: revokedAt == null ? null : fromDatabaseTime(revokedAt),
      expiresAt: expiresAt == null ? null : fromDatabaseTime(expiresAt),
      personId: row['person_id'] as String?,
    );
  }
}

import 'package:sqlite3/sqlite3.dart';
import 'package:xp_adapters/src/sqlite/sqlite_database.dart';
import 'package:xp_adapters/src/sqlite/timestamps.dart';
import 'package:xp_engine/xp_engine.dart';

/// Pairing tokens in the `pairing_token` table: only the hash of the secret.
class SqlitePairingTokenRepository implements PairingTokenRepository {
  /// Creates a repository over a database.
  const new(this._database);

  final SqliteDatabase _database;

  Database get _db => _database.connection;

  @override
  Future<void> add(PairingTokenRecord token) async {
    final usedAt = token.usedAt;
    _db.execute(
      'INSERT INTO pairing_token '
      '(id, hash, name, created_by, created_at, expires_at, used_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?)',
      [
        token.id,
        token.hash,
        token.name,
        token.createdBy,
        toDatabaseTime(token.createdAt),
        toDatabaseTime(token.expiresAt),
        if (usedAt == null) null else toDatabaseTime(usedAt),
      ],
    );
  }

  @override
  Future<PairingTokenRecord?> findByHash(String hash) async {
    final rows = _db.select(
      'SELECT id, hash, name, created_by, created_at, expires_at, used_at '
      'FROM pairing_token WHERE hash = ?',
      [hash],
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    final usedAt = row['used_at'] as int?;
    return PairingTokenRecord(
      id: row['id'] as String,
      hash: row['hash'] as String,
      name: row['name'] as String,
      createdBy: row['created_by'] as String,
      createdAt: fromDatabaseTime(row['created_at'] as int),
      expiresAt: fromDatabaseTime(row['expires_at'] as int),
      usedAt: usedAt == null ? null : fromDatabaseTime(usedAt),
    );
  }

  @override
  Future<bool> consume(String id, {required DateTime at}) async {
    final now = toDatabaseTime(at);
    _db.execute(
      'UPDATE pairing_token SET used_at = ? '
      'WHERE id = ? AND used_at IS NULL AND expires_at > ?',
      [now, id, now],
    );
    return _db.updatedRows > 0;
  }

  @override
  Future<void> prune({required DateTime before}) async {
    final limit = toDatabaseTime(before);
    _db.execute(
      'DELETE FROM pairing_token WHERE expires_at < ? OR used_at < ?',
      [limit, limit],
    );
  }
}

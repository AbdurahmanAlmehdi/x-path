import 'package:sqlite3/sqlite3.dart';
import 'package:xp_adapters/src/sqlite/sqlite_database.dart';
import 'package:xp_adapters/src/sqlite/timestamps.dart';
import 'package:xp_engine/xp_engine.dart';

/// Sign-in codes in the `sign_in_code` table: only the hash of the code.
///
/// Reads hit the database every time, so a code issued by `xpd person code`
/// works at once in a running engine.
class SqliteSignInCodeRepository implements SignInCodeRepository {
  /// Creates a repository over a database.
  const new(this._database);

  final SqliteDatabase _database;

  Database get _db => _database.connection;

  @override
  Future<void> add(SignInCodeRecord code) async {
    final usedAt = code.usedAt;
    _db.execute(
      'INSERT INTO sign_in_code '
      '(hash, person_id, created_at, expires_at, used_at) '
      'VALUES (?, ?, ?, ?, ?)',
      [
        code.hash,
        code.personId,
        toDatabaseTime(code.createdAt),
        toDatabaseTime(code.expiresAt),
        if (usedAt == null) null else toDatabaseTime(usedAt),
      ],
    );
  }

  @override
  Future<void> deleteUnused(
    String personId, {
    required DateTime expiredBefore,
  }) async {
    _db.execute(
      'DELETE FROM sign_in_code '
      'WHERE (person_id = ? AND used_at IS NULL) OR expires_at < ?',
      [personId, toDatabaseTime(expiredBefore)],
    );
  }

  @override
  Future<String?> use(String hash, {required DateTime at}) async {
    final now = toDatabaseTime(at);
    final rows = _db.select(
      'UPDATE sign_in_code SET used_at = ? '
      'WHERE hash = ? AND used_at IS NULL AND expires_at > ? '
      'RETURNING person_id',
      [now, hash, now],
    );
    return rows.isEmpty ? null : rows.single['person_id'] as String;
  }
}

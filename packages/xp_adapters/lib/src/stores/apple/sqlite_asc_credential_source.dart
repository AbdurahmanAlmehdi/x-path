import 'package:xp_adapters/src/sqlite/sqlite_database.dart';
import 'package:xp_engine/xp_engine.dart';

/// Finds the API key of an app through the `asc_key` credential assigned to
/// the flavor with its iOS bundle id (ADR 0013).
///
/// The credential's `secret_key` names a secret in the secret store whose value
/// is the JSON of an [AscKey] (`AscKey.toSecret`). The credential endpoints
/// write it (Phase 10c); a flavor without the reference, such as an Apple ID
/// flavor, has no key here.
class SqliteAscCredentialSource implements AscCredentialSource {
  /// Creates a source over the database and the secret store.
  const new({required this._database, required this._secrets});

  final SqliteDatabase _database;
  final SecretStore _secrets;

  /// The key, or `null` if no flavor with [bundleId] has an `asc_key`
  /// reference, its secret is missing or malformed, or the secrets cannot be
  /// read (a locked store makes every credential check a warning, not a crash).
  @override
  Future<AscKey?> forBundleId(String bundleId) async {
    final rows = _database.connection.select(
      'SELECT credential.secret_key FROM credential_assignment '
      'JOIN credential ON credential.id = credential_assignment.credential_id '
      'JOIN flavor ON flavor.id = credential_assignment.flavor_id '
      'WHERE flavor.ios_bundle_id = ? '
      "AND credential_assignment.kind = 'asc_key' "
      'ORDER BY credential_assignment.rowid LIMIT 1',
      [bundleId],
    );
    if (rows.isEmpty) return null;
    try {
      final json = await _secrets.read(rows.single['secret_key'] as String);
      return json == null ? null : AscKey.fromSecret(json);
    } on SecretStoreException {
      return null;
    } on FormatException {
      return null;
    }
  }
}

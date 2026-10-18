import 'package:xp_adapters/src/sqlite/sqlite_database.dart';
import 'package:xp_engine/xp_engine.dart';

/// Finds the service account of an app through the `play_sa` credential
/// assigned to the flavor with its Android application id (ADR 0013).
///
/// The credential's `secret_key` names a secret in the secret store whose value
/// is the JSON key file of the service account (`PlayServiceAccount`). The
/// credential endpoints write it (Phase 10c); a flavor without the reference
/// has no account here, and its release is uploaded by hand (D-15).
class SqlitePlayCredentialSource implements PlayCredentialSource {
  /// Creates a source over the database and the secret store.
  const new({required this._database, required this._secrets});

  final SqliteDatabase _database;
  final SecretStore _secrets;

  /// The account, or `null` if no flavor with [androidAppId] has a `play_sa`
  /// reference, its secret is missing or malformed, or the secrets cannot be
  /// read (a locked store makes every credential check a warning, not a crash).
  @override
  Future<PlayServiceAccount?> forAndroidAppId(String androidAppId) async {
    final rows = _database.connection.select(
      'SELECT credential.secret_key FROM credential_assignment '
      'JOIN credential ON credential.id = credential_assignment.credential_id '
      'JOIN flavor ON flavor.id = credential_assignment.flavor_id '
      'WHERE flavor.android_app_id = ? '
      "AND credential_assignment.kind = 'play_sa' "
      'ORDER BY credential_assignment.rowid LIMIT 1',
      [androidAppId],
    );
    if (rows.isEmpty) return null;
    try {
      final json = await _secrets.read(rows.single['secret_key'] as String);
      return json == null ? null : PlayServiceAccount.fromSecret(json);
    } on SecretStoreException {
      return null;
    } on FormatException {
      return null;
    }
  }
}

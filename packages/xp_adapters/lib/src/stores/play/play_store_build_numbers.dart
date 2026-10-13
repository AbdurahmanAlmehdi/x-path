import 'package:xp_engine/xp_engine.dart';

/// The version codes Google Play has seen for an app: the Play side of the
/// [StoreBuildNumbers] port for the `buildNumberReuse` guard check (D-11,
/// D-22).
///
/// Play refuses a version code it has seen on any track, so the list is every
/// Android App Bundle of the app (`edits.bundles.list`), read in a short edit
/// that is deleted again. Needs a service account; without one, or when Play
/// cannot be read, the answer is `null`. It answers for Android only: the
/// Apple half is `AscStoreBuildNumbers`, and `CombinedStoreBuildNumbers` asks
/// both.
class PlayStoreBuildNumbers implements StoreBuildNumbers {
  /// Creates the adapter.
  const new({required this._credentials, required this._connect});

  final PlayCredentialSource _credentials;
  final GooglePlayFactory _connect;

  /// The version codes of the Android app, or `null` if they cannot be read:
  /// no application id, no service account, or Google Play fails (an unknown
  /// package included).
  @override
  Future<StoreBuilds?> lookup({
    String? iosBundleId,
    String? androidAppId,
  }) async {
    if (androidAppId == null) return null;
    final account = await _credentials.forAndroidAppId(androidAppId);
    if (account == null) return null;
    final client = _connect(account);
    try {
      final edit = await client.insertEdit(androidAppId);
      try {
        final bundles = await client.bundles(androidAppId, edit.id);
        return StoreBuilds({for (final bundle in bundles) bundle.versionCode});
      } finally {
        try {
          await client.deleteEdit(androidAppId, edit.id);
        } on PlayException {
          // The edit expires by itself; the answer does not depend on it.
        }
      }
    } on PlayException {
      return null;
    }
  }
}

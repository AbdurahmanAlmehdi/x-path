import 'package:xp_engine/xp_engine.dart';

/// The build numbers App Store Connect has seen for an app: the Apple side of
/// the [StoreBuildNumbers] port for the `buildNumberReuse` guard check
/// (D-11, D-22).
///
/// Every build counts, whatever its processing state, and expired builds too:
/// App Store Connect refuses a build number it has seen. Needs an API key; an
/// Apple ID flavor cannot be asked (`null`). It answers for iOS only: Google
/// Play's version codes are the Play adapter's (Phase 10b), so an app that is
/// on both stores gets the Apple half here.
class AscStoreBuildNumbers implements StoreBuildNumbers {
  /// Creates the adapter.
  const new({required this._credentials, required this._connect});

  final AscCredentialSource _credentials;
  final AppStoreConnectFactory _connect;

  /// The build numbers of the iOS app, or `null` if they cannot be read: no
  /// iOS bundle id, no API key, or App Store Connect fails. An app that the
  /// team does not have yet has none.
  @override
  Future<StoreBuilds?> lookup({
    String? iosBundleId,
    String? androidAppId,
  }) async {
    if (iosBundleId == null) return null;
    final key = await _credentials.forBundleId(iosBundleId);
    if (key == null) return null;
    try {
      final client = _connect(key);
      final app = await client.findApp(iosBundleId);
      if (app == null) return const StoreBuilds({});
      final builds = await client.builds(app.id);
      return StoreBuilds({
        for (final build in builds) ?int.tryParse(build.buildNumber),
      });
    } on AppStoreConnectException {
      return null;
    }
  }
}

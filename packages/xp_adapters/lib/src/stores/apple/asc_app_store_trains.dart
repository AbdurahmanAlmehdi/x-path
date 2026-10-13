import 'package:xp_engine/xp_engine.dart';

/// The state of the App Store trains of an app: the [AppStoreTrains] port for
/// the `appStoreTrain` guard check (D-22, ITMS-90186).
///
/// Two sources, either of which may be missing:
///
/// - the **iTunes lookup** (no credentials, any flavor): the version on sale in
///   the app's storefront;
/// - **App Store Connect** (an API key): every version with its
///   `appVersionState`, which also knows the versions that are approved and
///   waiting for release. Their trains are closed, though nothing is on sale.
///
/// The live version is the higher of what both say. The answer is `null` only
/// if neither source could be read.
class AscAppStoreTrains implements AppStoreTrains {
  /// Creates the adapter.
  const new({
    required this._itunes,
    required this._credentials,
    required this._connect,
  });

  final ItunesLookup _itunes;
  final AscCredentialSource _credentials;
  final AppStoreConnectFactory _connect;

  @override
  Future<AppStoreTrainStatus?> status({
    required String bundleId,
    required String country,
  }) async {
    final live = <VersionName>[];
    final closed = <VersionName>{};
    var answered = false;

    try {
      final app = await _itunes.lookup(bundleId: bundleId, country: country);
      answered = true;
      final version = app == null ? null : _version(app.version);
      if (version != null) live.add(version);
    } on ItunesLookupException {
      // The other source may still answer.
    }

    try {
      final versions = await _storeVersions(bundleId);
      if (versions != null) {
        answered = true;
        for (final version in versions) {
          final name = _version(version.versionString);
          if (name == null) continue;
          if (version.state.isLive) live.add(name);
          if (version.state.isApprovedNotLive) closed.add(name);
        }
      }
    } on AppStoreConnectException {
      // A key that Apple refuses is the credential check's to report.
    }

    if (!answered) return null;
    return AppStoreTrainStatus(
      liveVersion: live.isEmpty ? null : live.reduce((a, b) => b > a ? b : a),
      closedVersions: closed,
    );
  }

  /// The versions of the app in App Store Connect, or `null` if there is no
  /// key for the app or the team has no such app.
  Future<List<AscAppStoreVersion>?> _storeVersions(String bundleId) async {
    final key = await _credentials.forBundleId(bundleId);
    if (key == null) return null;
    final client = _connect(key);
    final app = await client.findApp(bundleId);
    return app == null ? const [] : await client.versions(app.id);
  }

  VersionName? _version(String text) {
    try {
      return VersionName.parse(text);
    } on FormatException {
      return null;
    }
  }
}

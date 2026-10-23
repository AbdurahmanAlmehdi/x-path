import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';

/// The Apple side of the stores, wired for `xpd serve`: the iTunes lookup, an
/// App Store Connect client per API key, the `appStoreTrain` guard check, the
/// Apple build numbers (for `buildNumberReuse`, which `storeGuardChecks`
/// composes with Google Play's) and the `upload.appStore` step.
///
/// The API key of an app is found through the `asc_key` credential reference of
/// the flavor with its iOS bundle id (`SqliteAscCredentialSource`); an app
/// without one, such as an Apple ID flavor, gets the iTunes lookup only and no
/// build numbers.
class AppleStores {
  /// Creates the wiring over the engine database and secret store.
  ///
  /// `ascBaseUrl` and `itunesBaseUrl` replace the real servers in tests.
  new({
    required SqliteDatabase database,
    required SecretStore secrets,
    required this._clock,
    this._ascBaseUrl,
    Uri? itunesBaseUrl,
  }) : credentials = SqliteAscCredentialSource(
         database: database,
         secrets: secrets,
       ),
       _itunes = HttpItunesLookup(baseUrl: itunesBaseUrl, clock: _clock) {
    trains = AscAppStoreTrains(
      itunes: _itunes,
      credentials: credentials,
      connect: connect,
    );
    buildNumbers = AscStoreBuildNumbers(
      credentials: credentials,
      connect: connect,
    );
  }

  final Clock _clock;
  final Uri? _ascBaseUrl;
  final HttpItunesLookup _itunes;
  final _clients = <AscKey, HttpAppStoreConnect>{};

  /// Finds the API key of an app.
  final AscCredentialSource credentials;

  /// The public iTunes lookup, which an Apple ID flavor is read through.
  ItunesLookup get itunes => _itunes;

  /// The state of the App Store trains of an app.
  late final AppStoreTrains trains;

  /// The Apple half of the build numbers the stores have seen.
  late final StoreBuildNumbers buildNumbers;

  /// The client for [key]: one per key, so that its token is reused.
  AppStoreConnect connect(AscKey key) => _clients.putIfAbsent(
    key,
    () => HttpAppStoreConnect(key: key, clock: _clock, baseUrl: _ascBaseUrl),
  );

  /// The guard checks that need Apple alone: `appStoreTrain`.
  List<GuardCheck> get guardChecks => [AppStoreTrainCheck(trains)];

  /// The `upload.appStore` step, uploading from the artifact [store].
  ///
  /// [processingTimeout] replaces the 30 minutes a build upload may take, and
  /// the upload is then polled every second (end-to-end tests).
  UploadAppStoreStep uploadStep({
    required ArtifactRepository repository,
    required LocalArtifactStore store,
    required SecretStore secrets,
    required bool isMacOS,
    Duration? processingTimeout,
  }) => UploadAppStoreStep(
    repository: repository,
    store: store,
    secrets: secrets,
    connect: connect,
    isMacOS: isMacOS,
    pollInterval: Duration(seconds: processingTimeout == null ? 15 : 1),
    processingTimeout: processingTimeout ?? const Duration(minutes: 30),
  );

  /// Releases the HTTP clients.
  void close() {
    _itunes.close();
    for (final client in _clients.values) {
      client.close();
    }
    _clients.clear();
  }
}

import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';

/// The environment variable that overrides the target API level Google Play
/// asks for (`xpd serve`).
const playTargetSdkVariable = 'XPD_PLAY_TARGET_SDK';

/// The Google Play side of the stores, wired for `xpd serve`: a Developer API
/// client per service account, the `playTargetSdk` guard check, the Play
/// version codes (for `buildNumberReuse`, which `storeGuardChecks` composes
/// with Apple's) and the `upload.play` step.
///
/// The service account of an app is found through the `play_sa` credential
/// reference of the flavor with its Android application id
/// (`SqlitePlayCredentialSource`); an app without one is released to Play by
/// hand (D-15) and gets no version codes.
class PlayStores {
  /// Creates the wiring over the engine database and secret store.
  ///
  /// `requiredTargetSdk` is the API level Play asks for (the built-in default
  /// if absent). `apiBaseUrl` and `uploadBaseUrl` replace Google's servers in
  /// tests.
  new({
    required SqliteDatabase database,
    required SecretStore secrets,
    required this._clock,
    int? requiredTargetSdk,
    this._apiBaseUrl,
    this._uploadBaseUrl,
  }) : credentials = SqlitePlayCredentialSource(
         database: database,
         secrets: secrets,
       ),
       requirements = ConfiguredPlayRequirements(
         requiredTargetSdk ?? defaultPlayTargetSdk,
       ) {
    buildNumbers = PlayStoreBuildNumbers(
      credentials: credentials,
      connect: connect,
    );
  }

  /// The API level named by [value], the text of [playTargetSdkVariable]; the
  /// built-in default if [value] is `null`.
  ///
  /// Throws a [FormatException] if it is not a whole number from 21 to 99.
  static int targetSdkFrom(String? value) {
    if (value == null) return defaultPlayTargetSdk;
    final level = int.tryParse(value.trim());
    if (level == null || level < 21 || level > 99) {
      throw FormatException(
        '$playTargetSdkVariable must be an API level such as '
        '$defaultPlayTargetSdk, not "$value".',
      );
    }
    return level;
  }

  final Clock _clock;
  final Uri? _apiBaseUrl;
  final Uri? _uploadBaseUrl;
  final _clients = <PlayServiceAccount, HttpGooglePlay>{};

  /// Finds the service account of an app.
  final PlayCredentialSource credentials;

  /// The target API level Play asks for.
  final PlayRequirements requirements;

  /// The Play half of the build numbers the stores have seen.
  late final StoreBuildNumbers buildNumbers;

  /// The client for [account]: one per account, so that its token is reused.
  GooglePlay connect(PlayServiceAccount account) => _clients.putIfAbsent(
    account,
    () => HttpGooglePlay(
      account: account,
      clock: _clock,
      apiBaseUrl: _apiBaseUrl,
      uploadBaseUrl: _uploadBaseUrl,
    ),
  );

  /// The guard checks that need Google Play alone: `playTargetSdk`.
  List<GuardCheck> get guardChecks => [PlayTargetSdkCheck(requirements)];

  /// The `upload.play` step, uploading from the artifact [store].
  UploadPlayStep uploadStep({
    required ArtifactRepository repository,
    required ArtifactStore store,
    required SecretStore secrets,
  }) => UploadPlayStep(
    repository: repository,
    store: store,
    secrets: secrets,
    connect: connect,
  );

  /// Releases the HTTP clients.
  void close() {
    for (final client in _clients.values) {
      client.close();
    }
    _clients.clear();
  }
}

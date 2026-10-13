import 'package:equatable/equatable.dart';
import 'package:xp_engine/src/versioning/app_version.dart';

/// What App Store Connect says about the versions of an app.
class AppStoreTrainStatus extends Equatable {
  /// Creates a status.
  const new({this.liveVersion, this.closedVersions = const {}});

  /// The version on sale now, or `null` if the app has none yet.
  final VersionName? liveVersion;

  /// Versions whose train is closed without being live: approved and waiting
  /// for release. A build for a closed train is rejected.
  final Set<VersionName> closedVersions;

  @override
  List<Object?> get props => [liveVersion, closedVersions];
}

/// The state of the App Store trains of an app (D-22, ITMS-90186).
///
/// The iTunes lookup (live version) and App Store Connect (approved versions)
/// implement it in Phase 10a.
abstract interface class AppStoreTrains {
  /// The status of the app with [bundleId] in the storefront [country], or
  /// `null` if it cannot be read.
  Future<AppStoreTrainStatus?> status({
    required String bundleId,
    required String country,
  });
}

/// The Google Play target API level that new releases must reach (D-22).
///
/// Phase 10b implements it.
abstract interface class PlayRequirements {
  /// The lowest `targetSdk` Play accepts for an update now, or `null` if it
  /// is not known.
  Future<int?> requiredTargetSdk();
}

/// A Shorebird release of an app.
class ShorebirdRelease extends Equatable {
  /// Creates a release record.
  const new({
    required this.version,
    required this.flutterVersion,
    this.activePlatforms = const {},
  });

  /// The release version as Shorebird names it, `x.y.z+build`.
  final AppVersion version;

  /// The Flutter version the release was built with. A patch uses it (D-20).
  /// `null` for a release that Shorebird has no Flutter version for (releases
  /// made by old CLI versions).
  final String? flutterVersion;

  /// The platforms (`android`, `ios`) the release is complete for. A platform
  /// whose release was started and never finished is not in it.
  final Set<String> activePlatforms;

  @override
  List<Object?> get props => [version, flutterVersion, activePlatforms];
}

/// What Shorebird knows about the releases of an app.
///
/// `xp_adapters` implements it over `shorebird releases list --json`.
abstract interface class ShorebirdReleases {
  /// The releases of the Shorebird app [appId], or `null` if they cannot be
  /// listed.
  ///
  /// [tokenSecret] is the key in the secret store of the Shorebird API key
  /// (`SHOREBIRD_TOKEN`); without it the CLI uses whatever login the machine
  /// has.
  Future<List<ShorebirdRelease>?> releases(String appId, {String? tokenSecret});
}

/// An [AppStoreTrains] with the answer the test gives it.
class FakeAppStoreTrains implements AppStoreTrains {
  /// Creates a fake that answers [answer]; `null` means unreadable.
  new([this.answer]);

  /// The answer.
  AppStoreTrainStatus? answer;

  /// Every call as `bundleId country`, oldest first.
  final lookups = <String>[];

  @override
  Future<AppStoreTrainStatus?> status({
    required String bundleId,
    required String country,
  }) async {
    lookups.add('$bundleId $country');
    return answer;
  }
}

/// A [PlayRequirements] with the answer the test gives it.
class FakePlayRequirements implements PlayRequirements {
  /// Creates a fake that answers [answer]; `null` means unknown.
  new([this.answer]);

  /// The answer.
  int? answer;

  @override
  Future<int?> requiredTargetSdk() async => answer;
}

/// A [ShorebirdReleases] with the answer the test gives it.
class FakeShorebirdReleases implements ShorebirdReleases {
  /// Creates a fake that lists [answer]; `null` means unlistable.
  new([this.answer]);

  /// The answer.
  List<ShorebirdRelease>? answer;

  /// The app id of every call, oldest first.
  final lookups = <String>[];

  /// The `tokenSecret` of every call, oldest first.
  final tokenSecrets = <String?>[];

  @override
  Future<List<ShorebirdRelease>?> releases(
    String appId, {
    String? tokenSecret,
  }) async {
    lookups.add(appId);
    tokenSecrets.add(tokenSecret);
    return answer;
  }
}

import 'package:equatable/equatable.dart';
import 'package:xp_engine/src/versioning/app_version.dart';

/// A platform Shorebird releases and patches.
enum ShorebirdPlatform {
  /// An Android release (APK or AAB).
  android('android'),

  /// An iOS release (IPA).
  ios('ios');

  new(this.wire);

  /// The name on the Shorebird command line and in the database.
  final String wire;

  /// The platform called [wire], or `null`.
  static ShorebirdPlatform? fromWire(String wire) =>
      values.where((platform) => platform.wire == wire).firstOrNull;
}

/// The Flutter version a Shorebird release was built with (D-20).
///
/// A patch is built with the Flutter version of the release it patches, so
/// `shorebird.release` saves it here, keyed by what Shorebird keys a release
/// by.
class ShorebirdReleaseRecord extends Equatable {
  /// Creates a record.
  const new({
    required this.appId,
    required this.version,
    required this.platform,
    required this.flutterVersion,
    required this.jobId,
    required this.recordedAt,
  });

  /// The Shorebird app id (`app_id` of `shorebird.yaml`).
  final String appId;

  /// The release version, `x.y.z+build`.
  final AppVersion version;

  /// The platform released.
  final ShorebirdPlatform platform;

  /// The Flutter version the release was built with, such as `3.47.6`.
  final String flutterVersion;

  /// The job that made the release; its artifacts (the R8 mapping, the
  /// symbols) belong to the release.
  final String jobId;

  /// When it was recorded.
  final DateTime recordedAt;

  @override
  List<Object?> get props => [
    appId,
    version,
    platform,
    flutterVersion,
    jobId,
    recordedAt,
  ];
}

/// Where the records of Shorebird releases are kept.
///
/// `xp_adapters` has the SQLite implementation.
abstract interface class ShorebirdReleaseRepository {
  /// Stores [record], replacing the one for the same app, version and
  /// platform.
  Future<void> save(ShorebirdReleaseRecord record);

  /// The record of the release [version] of [appId] for [platform], or
  /// `null`.
  Future<ShorebirdReleaseRecord?> find(
    String appId,
    AppVersion version,
    ShorebirdPlatform platform,
  );

  /// The Flutter versions the recorded releases were built with. Every patch
  /// of a release must use its version (D-20), so these SDKs stay in the
  /// cache.
  Future<Set<String>> flutterVersions();
}

/// A [ShorebirdReleaseRepository] that forgets everything on exit.
class InMemoryShorebirdReleaseRepository implements ShorebirdReleaseRepository {
  final _records = <String, ShorebirdReleaseRecord>{};

  static String _key(
    String appId,
    AppVersion version,
    ShorebirdPlatform platform,
  ) => '$appId $version ${platform.wire}';

  @override
  Future<void> save(ShorebirdReleaseRecord record) async =>
      _records[_key(record.appId, record.version, record.platform)] = record;

  @override
  Future<ShorebirdReleaseRecord?> find(
    String appId,
    AppVersion version,
    ShorebirdPlatform platform,
  ) async => _records[_key(appId, version, platform)];

  @override
  Future<Set<String>> flutterVersions() async => {
    for (final record in _records.values) record.flutterVersion,
  };
}

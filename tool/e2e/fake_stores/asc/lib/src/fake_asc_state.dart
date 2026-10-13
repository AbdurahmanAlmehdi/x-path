/// An app of the fake server.
class FakeAscApp {
  /// Creates an app.
  new({required this.id, required this.bundleId, required this.name});

  /// The id (the numeric Apple id).
  final String id;

  /// The bundle id.
  final String bundleId;

  /// The name.
  final String name;
}

/// A build of the fake server.
class FakeAscBuild {
  /// Creates a build.
  new({
    required this.id,
    required this.appId,
    required this.buildNumber,
    required this.shortVersion,
    required this.processingState,
    required this.uploadedDate,
    this.expired = false,
  });

  /// The id.
  final String id;

  /// The app it belongs to.
  final String appId;

  /// The build number (`CFBundleVersion`).
  final String buildNumber;

  /// The marketing version of its train.
  final String shortVersion;

  /// `PROCESSING`, `FAILED`, `INVALID` or `VALID`.
  String processingState;

  /// When it was uploaded.
  final DateTime uploadedDate;

  /// Whether it expired.
  bool expired;
}

/// An App Store version of the fake server.
class FakeAscVersion {
  /// Creates a version.
  new({
    required this.id,
    required this.appId,
    required this.versionString,
    required this.appVersionState,
    required this.createdDate,
    this.platform = 'IOS',
  });

  /// The id.
  final String id;

  /// The app it belongs to.
  final String appId;

  /// The marketing version.
  final String versionString;

  /// `appVersionState`, such as `READY_FOR_DISTRIBUTION`.
  String appVersionState;

  /// When it was created.
  final DateTime createdDate;

  /// `IOS`, ...
  final String platform;
}

/// A review submission of the fake server.
class FakeAscSubmission {
  /// Creates a submission.
  new({
    required this.id,
    required this.appId,
    required this.platform,
    this.state = 'READY_FOR_REVIEW',
  });

  /// The id.
  final String id;

  /// The app it belongs to.
  final String appId;

  /// `IOS`, ...
  final String platform;

  /// `READY_FOR_REVIEW`, `WAITING_FOR_REVIEW`, ...
  String state;

  /// The versions it holds.
  final versionIds = <String>[];

  /// When it was submitted.
  DateTime? submittedDate;
}

/// A phased release of the fake server.
class FakeAscPhasedRelease {
  /// Creates a phased release of the version [versionId].
  new({
    required this.id,
    required this.versionId,
    this.state = 'INACTIVE',
    this.currentDayNumber,
  });

  /// The id.
  final String id;

  /// The version it belongs to.
  final String versionId;

  /// `INACTIVE`, `ACTIVE`, `PAUSED` or `COMPLETE`.
  String state;

  /// The day of the rollout.
  int? currentDayNumber;
}

/// What the iTunes lookup of the fake server knows about an app.
class FakeItunesEntry {
  /// Creates an entry.
  new({
    required this.bundleId,
    required this.trackId,
    required this.version,
    this.releaseDate = '2026-09-01T10:00:00Z',
  });

  /// The bundle id.
  final String bundleId;

  /// The numeric Apple id.
  final String trackId;

  /// The version on sale.
  final String version;

  /// `currentVersionReleaseDate`.
  final String releaseDate;
}

/// A request the fake server received.
class FakeAscRequest {
  /// Creates a record.
  const new({
    required this.method,
    required this.uri,
    required this.body,
    required this.tokenProblem,
  });

  /// `GET`, `POST`, ...
  final String method;

  /// The path and query.
  final Uri uri;

  /// The decoded JSON body, if there was one.
  final Object? body;

  /// Why the token was refused, or `null` if it was accepted (or the path
  /// needs none).
  final String? tokenProblem;

  @override
  String toString() => '$method ${uri.path}';
}

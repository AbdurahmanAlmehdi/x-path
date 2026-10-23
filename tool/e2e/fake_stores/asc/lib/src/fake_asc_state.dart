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

/// An error or warning of a build upload of the fake server.
class FakeAscIssue {
  /// Creates an issue.
  const new(this.code, this.description);

  /// The code, such as `90189`.
  final String code;

  /// What it says.
  final String description;
}

/// How the fake server ends a build upload once its file is in.
class FakeAscUploadOutcome {
  /// The upload completes and becomes a build, with [warnings].
  const new complete({this.warnings = const []})
    : errors = const [],
      stalls = false;

  /// The upload fails with [errors].
  const new rejected(this.errors) : warnings = const [], stalls = false;

  /// The upload stays `PROCESSING` for good.
  const new stalled() : errors = const [], warnings = const [], stalls = true;

  /// Why it fails; empty when it does not.
  final List<FakeAscIssue> errors;

  /// What it warns about.
  final List<FakeAscIssue> warnings;

  /// Whether it never ends.
  final bool stalls;
}

/// A build upload of the fake server.
class FakeAscBuildUpload {
  /// Creates an upload.
  new({
    required this.id,
    required this.appId,
    required this.version,
    required this.buildNumber,
    required this.outcome,
  });

  /// The id.
  final String id;

  /// The app it belongs to.
  final String appId;

  /// `cfBundleShortVersionString`.
  final String version;

  /// `cfBundleVersion`.
  final String buildNumber;

  /// How it ends.
  final FakeAscUploadOutcome outcome;

  /// `AWAITING_UPLOAD`, `PROCESSING`, `COMPLETE` or `FAILED`.
  String state = 'AWAITING_UPLOAD';

  /// Its file, once it was created.
  FakeAscUploadFile? file;

  /// How often it was read while processing.
  int polls = 0;

  /// The build it became.
  FakeAscBuild? build;
}

/// The file of a build upload of the fake server.
class FakeAscUploadFile {
  /// Creates a file of [fileSize] bytes, sent in parts of [partSize].
  new({
    required this.id,
    required this.uploadId,
    required this.fileName,
    required this.fileSize,
    required this.partSize,
  });

  /// The id.
  final String id;

  /// The build upload it belongs to.
  final String uploadId;

  /// The name of the IPA.
  final String fileName;

  /// Its size in bytes.
  final int fileSize;

  /// The size of each part but the last.
  final int partSize;

  /// The parts received, by number from 0.
  final parts = <int, List<int>>{};

  /// Whether the client marked it uploaded.
  bool uploaded = false;

  /// How many parts the file is sent in.
  int get partCount =>
      fileSize == 0 ? 1 : (fileSize + partSize - 1) ~/ partSize;

  /// The bytes received, in order, if every part is in.
  List<int>? get bytes => parts.length == partCount
      ? [for (var part = 0; part < partCount; part++) ...parts[part]!]
      : null;
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
    this.authorization,
  });

  /// `GET`, `POST`, ...
  final String method;

  /// The path and query.
  final Uri uri;

  /// The decoded JSON body, if there was one; the bytes of a part of a build
  /// upload.
  final Object? body;

  /// Why the token was refused, or `null` if it was accepted (or the path
  /// needs none).
  final String? tokenProblem;

  /// The `Authorization` header, if the request had one.
  final String? authorization;

  @override
  String toString() => '$method ${uri.path}';
}

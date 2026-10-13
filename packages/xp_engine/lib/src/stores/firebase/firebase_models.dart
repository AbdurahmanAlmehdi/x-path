import 'package:equatable/equatable.dart';

/// A release in Firebase App Distribution (`projects.apps.releases`).
class FirebaseRelease extends Equatable {
  /// Creates a release.
  const new({
    required this.name,
    this.displayVersion,
    this.buildVersion,
    this.releaseNotes,
    this.firebaseConsoleUri,
    this.testingUri,
  });

  /// The resource name, `projects/{number}/apps/{appId}/releases/{id}`.
  final String name;

  /// The version name of the binary (`CFBundleShortVersionString`,
  /// `versionName`).
  final String? displayVersion;

  /// The build number of the binary (`CFBundleVersion`, `versionCode`).
  final String? buildVersion;

  /// The text of the release notes.
  final String? releaseNotes;

  /// The release in the Firebase console.
  final String? firebaseConsoleUri;

  /// The page where testers install the release.
  final String? testingUri;

  @override
  List<Object?> get props => [
    name,
    displayVersion,
    buildVersion,
    releaseNotes,
    firebaseConsoleUri,
    testingUri,
  ];
}

/// What an upload did to the releases (`UploadReleaseResponse.result`).
enum FirebaseUploadResult {
  /// A release was made.
  created('RELEASE_CREATED'),

  /// The release of the same version existed and took the new binary.
  updated('RELEASE_UPDATED'),

  /// The release of the same version existed with the same binary.
  unmodified('RELEASE_UNMODIFIED'),

  /// A result this version of XPath does not know.
  unknown('');

  new(this.wire);

  /// The value the API uses.
  final String wire;

  /// The result called [wire]; [unknown] for any other.
  static FirebaseUploadResult fromWire(String? wire) => values.firstWhere(
    (result) => result.wire == wire && result != unknown,
    orElse: () => unknown,
  );
}

/// A long-running operation, as the upload and `operations.get` answer.
class FirebaseOperation extends Equatable {
  /// Creates an operation.
  const new({
    required this.name,
    this.done = false,
    this.release,
    this.result = FirebaseUploadResult.unknown,
    this.error,
  });

  /// The resource name to poll.
  final String name;

  /// Whether the operation has ended.
  final bool done;

  /// The release the upload made or found; only when [done] without [error].
  final FirebaseRelease? release;

  /// What the upload did.
  final FirebaseUploadResult result;

  /// Why the operation failed, when it did.
  final String? error;

  @override
  List<Object?> get props => [name, done, release, result, error];
}

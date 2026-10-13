/// A release in a track of the fake server.
class FakePlayRelease {
  /// Creates a release.
  new({
    required this.versionCodes,
    this.status = 'completed',
    this.name,
    this.userFraction,
    this.releaseNotes = const [],
    this.lifecycleState = 'RELEASE_LIFECYCLE_STATE_PUBLISHED',
  });

  /// The version codes.
  final List<int> versionCodes;

  /// `draft`, `inProgress`, `halted` or `completed`.
  String status;

  /// The release name.
  String? name;

  /// The fraction of users.
  double? userFraction;

  /// The release notes as `{language, text}` objects.
  List<Map<String, Object?>> releaseNotes;

  /// `releaseLifecycleState`, such as `RELEASE_LIFECYCLE_STATE_IN_REVIEW`.
  String lifecycleState;

  /// Whether the release is in review.
  bool get inReview => lifecycleState == 'RELEASE_LIFECYCLE_STATE_IN_REVIEW';

  /// The release as the edit API (`TrackRelease`) writes it.
  Map<String, Object?> toTrackRelease() => {
    'name': ?name,
    'versionCodes': [for (final code in versionCodes) '$code'],
    'status': status,
    'userFraction': ?userFraction,
    if (releaseNotes.isNotEmpty) 'releaseNotes': releaseNotes,
  };
}

/// An Android App Bundle of the fake server.
class FakePlayBundle {
  /// Creates a bundle.
  const new({
    required this.versionCode,
    required this.sha1,
    required this.sha256,
  });

  /// The version code.
  final int versionCode;

  /// The SHA-1 of the uploaded bytes.
  final String sha1;

  /// The SHA-256 of the uploaded bytes.
  final String sha256;

  /// The bundle as the API writes it.
  Map<String, Object?> toJson() => {
    'versionCode': versionCode,
    'sha1': sha1,
    'sha256': sha256,
  };
}

/// An app of the fake server.
class FakePlayApp {
  /// Creates an app.
  new(this.packageName, {this.allowedAccounts});

  /// The application id.
  final String packageName;

  /// The service accounts (by email) that may release the app, or `null` for
  /// every account the server knows.
  Set<String>? allowedAccounts;

  /// The committed bundles, by version code.
  final bundles = <int, FakePlayBundle>{};

  /// The committed releases of each track.
  final tracks = <String, List<FakePlayRelease>>{};

  /// The names of the releases whose review a commit cancelled, oldest first.
  /// A commit with `ERROR_IF_IN_REVIEW` never adds to it.
  final cancelledReviews = <String>[];

  /// Whether any release of the app is in review.
  bool get reviewInProgress =>
      [for (final releases in tracks.values) ...releases]
          .any((release) => release.inReview);

  /// Puts a release in a track as if an earlier commit made it.
  FakePlayRelease addRelease(
    String track,
    List<int> versionCodes, {
    String status = 'completed',
    String lifecycleState = 'RELEASE_LIFECYCLE_STATE_PUBLISHED',
    String? name,
    double? userFraction,
  }) {
    final release = FakePlayRelease(
      versionCodes: versionCodes,
      status: status,
      lifecycleState: lifecycleState,
      name: name,
      userFraction: userFraction,
    );
    tracks.putIfAbsent(track, () => []).add(release);
    for (final code in versionCodes) {
      bundles.putIfAbsent(
        code,
        () => FakePlayBundle(versionCode: code, sha1: '', sha256: ''),
      );
    }
    return release;
  }
}

/// An edit of the fake server.
class FakePlayEdit {
  /// Creates an edit.
  new({required this.id, required this.packageName, required this.expiresAt});

  /// The id.
  final String id;

  /// The app.
  final String packageName;

  /// When the edit expires.
  final DateTime expiresAt;

  /// The bundles uploaded in the edit, by version code.
  final bundles = <int, FakePlayBundle>{};

  /// The tracks changed in the edit, by name.
  final tracks = <String, List<FakePlayRelease>>{};

  /// Whether the edit was deleted.
  bool deleted = false;

  /// Whether the edit was committed.
  bool committed = false;
}

/// A commit the fake server received.
class FakePlayCommit {
  /// Creates a record.
  const new({
    required this.editId,
    required this.changesInReviewBehavior,
    required this.status,
    required this.cancelledReview,
  });

  /// The edit.
  final String editId;

  /// The `changesInReviewBehavior` query parameter, or `null` if the commit
  /// did not send it (which means: cancel a review in progress).
  final String? changesInReviewBehavior;

  /// The HTTP status the commit was answered with.
  final int status;

  /// Whether the commit cancelled a review that was in progress.
  final bool cancelledReview;
}

/// A request the fake server received.
class FakePlayRequest {
  /// Creates a record.
  const new({
    required this.method,
    required this.uri,
    required this.body,
    required this.bodyLength,
    required this.contentType,
    required this.tokenProblem,
  });

  /// `GET`, `POST`, ...
  final String method;

  /// The path and query.
  final Uri uri;

  /// The decoded JSON body, if there was one and it is JSON.
  final Object? body;

  /// The number of bytes in the body.
  final int bodyLength;

  /// The `Content-Type` of the request, if it had one.
  final String? contentType;

  /// Why the bearer token was refused, or `null` if it was accepted (or the
  /// path needs none).
  final String? tokenProblem;

  @override
  String toString() => '$method ${uri.path}';
}

import 'package:equatable/equatable.dart';

/// An open edit: the transaction Google Play changes go through. Nothing is
/// published until it is committed.
class PlayEdit extends Equatable {
  /// Creates an edit.
  const new({required this.id, this.expiresAt});

  /// The id to use in the calls that follow.
  final String id;

  /// When Google Play drops the edit, if it said.
  final DateTime? expiresAt;

  @override
  List<Object?> get props => [id, expiresAt];
}

/// An Android App Bundle in an edit.
class PlayBundle extends Equatable {
  /// Creates a bundle.
  const new({required this.versionCode, this.sha256});

  /// The version code from the manifest of the bundle: the build number.
  final int versionCode;

  /// The SHA-256 of the uploaded bytes, in hexadecimal, if Play said.
  final String? sha256;

  @override
  List<Object?> get props => [versionCode, sha256];
}

/// The status of a release in a track (`TrackRelease.status`).
enum PlayReleaseStatus {
  /// Not served to anyone; can still be edited and sent to review later.
  draft('draft'),

  /// Served to a fraction of the users (`userFraction`).
  inProgress('inProgress'),

  /// Stopped; users who have it keep it.
  halted('halted'),

  /// Served to all users.
  completed('completed'),

  /// A status this version of XPath does not know.
  unknown('');

  new(this.wire);

  /// The value the API uses.
  final String wire;

  /// The status called [wire]; [unknown] for any other.
  static PlayReleaseStatus fromWire(String? wire) => values.firstWhere(
    (status) => status.wire == wire && status != unknown,
    orElse: () => unknown,
  );
}

/// A release in a track.
class PlayRelease extends Equatable {
  /// Creates a release.
  const new({
    required this.versionCodes,
    required this.status,
    this.userFraction,
    this.name,
    this.releaseNotes = const {},
  });

  /// The version codes in the release.
  final List<int> versionCodes;

  /// Where the release is.
  final PlayReleaseStatus status;

  /// The fraction of users, `0 < f < 1`, for `inProgress` and `halted`.
  final double? userFraction;

  /// The name of the release; Play makes one from the version name if absent.
  final String? name;

  /// The release notes, by language tag (`en-US`).
  final Map<String, String> releaseNotes;

  @override
  List<Object?> get props => [
    versionCodes,
    status,
    userFraction,
    name,
    releaseNotes,
  ];
}

/// A track of an app in an edit, with its releases.
class PlayTrack extends Equatable {
  /// Creates a track.
  const new({required this.name, this.releases = const []});

  /// The track: `internal`, `alpha`, `beta`, `production` or a custom name.
  final String name;

  /// Its releases.
  final List<PlayRelease> releases;

  @override
  List<Object?> get props => [name, releases];
}

/// Where a release is in review (`releaseLifecycleState`).
enum PlayLifecycleState {
  /// Not ready yet; can still be edited.
  draft('RELEASE_LIFECYCLE_STATE_DRAFT'),

  /// Ready to be sent for review; the developer has to act.
  notSentForReview('RELEASE_LIFECYCLE_STATE_NOT_SENT_FOR_REVIEW'),

  /// Submitted and in review.
  inReview('RELEASE_LIFECYCLE_STATE_IN_REVIEW'),

  /// Passed review; the developer publishes it by hand.
  approvedNotPublished('RELEASE_LIFECYCLE_STATE_APPROVED_NOT_PUBLISHED'),

  /// Rejected in review.
  notApproved('RELEASE_LIFECYCLE_STATE_NOT_APPROVED'),

  /// Available to users on the track, fully or partly rolled out.
  published('RELEASE_LIFECYCLE_STATE_PUBLISHED'),

  /// A state this version of XPath does not know.
  unknown('');

  new(this.wire);

  /// The value the API uses.
  final String wire;

  /// The state called [wire]; [unknown] for any other.
  static PlayLifecycleState fromWire(String? wire) => values.firstWhere(
    (state) => state.wire == wire && state != unknown,
    orElse: () => unknown,
  );
}

/// A release of a track as `tracks.releases.list` reports it: committed
/// releases only, with their review state.
class PlayReleaseSummary extends Equatable {
  /// Creates a summary.
  const new({
    required this.track,
    required this.state,
    this.name,
    this.versionCodes = const [],
  });

  /// The track.
  final String track;

  /// The release name, if Play gave one.
  final String? name;

  /// Where the release is in review.
  final PlayLifecycleState state;

  /// The version codes of its active artifacts.
  final List<int> versionCodes;

  @override
  List<Object?> get props => [track, name, state, versionCodes];
}

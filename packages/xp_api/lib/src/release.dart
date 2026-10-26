// `json_serializable` cannot parse `factory .name` constructors yet.
// ignore_for_file: unnecessary_type_name_in_constructor

import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'release.g.dart';

/// Where a release is (D-17).
///
/// `draft → building → uploaded → in_review → (rejected | approved) → live →
/// merged`, plus `abandoned`. The engine derives it from the progress of the
/// jobs of the release and the status of each store.
@JsonEnum(valueField: 'wire')
enum ReleaseState {
  /// Dispatched; no build has started.
  draft('draft'),

  /// A build runs, or the uploads are not all done.
  building('building'),

  /// Every store the release targets has the build.
  uploaded('uploaded'),

  /// A store reviews it.
  inReview('in_review'),

  /// A store rejected it. The owner can start a new build of the same
  /// version.
  rejected('rejected'),

  /// Every store approved it; at least one has not released it yet.
  approved('approved'),

  /// Every store targeted has it on sale. The release PR can be merged.
  live('live'),

  /// The release pull request was merged.
  merged('merged'),

  /// The owner gave the release up.
  abandoned('abandoned');

  new(this.wire);

  /// The name on the wire and in the database.
  final String wire;

  /// Whether the release is over: it never changes again.
  bool get isTerminal => this == merged || this == abandoned;
}

/// A store a release is uploaded to.
@JsonEnum(valueField: 'wire')
enum ReleaseStore {
  /// App Store Connect.
  apple('apple'),

  /// Google Play.
  play('play');

  new(this.wire);

  /// The name on the wire and in the database.
  final String wire;
}

/// Where the release is in one store.
@JsonEnum(valueField: 'wire')
enum StoreState {
  /// The build is not in the store yet.
  pending('pending'),

  /// The store has the build; it is not in review.
  uploaded('uploaded'),

  /// The store reviews it.
  inReview('in_review'),

  /// The store rejected it.
  rejected('rejected'),

  /// The store approved it; it is not on sale yet.
  approved('approved'),

  /// On sale.
  live('live');

  new(this.wire);

  /// The name on the wire and in the database.
  final String wire;
}

/// Where a store status came from.
@JsonEnum(valueField: 'wire')
enum StatusSource {
  /// The upload step: the store has the build.
  upload('upload'),

  /// The store's API (App Store Connect, `tracks.releases.list`).
  api('api'),

  /// The public iTunes lookup, for an Apple ID flavor.
  lookup('lookup'),

  /// The owner pressed the button of the store.
  manual('manual');

  new(this.wire);

  /// The name on the wire and in the database.
  final String wire;
}

/// The status of a release in one store.
@JsonSerializable(includeIfNull: false)
class StoreStatus extends Equatable {
  /// Creates a status.
  const new({
    required this.store,
    required this.state,
    required this.source,
    this.detail,
    this.checkedAt,
    this.changedAt,
    this.note,
  });

  /// Reads a status from its JSON form.
  factory StoreStatus.fromJson(Map<String, dynamic> json) =>
      _$StoreStatusFromJson(json);

  /// Which store.
  final ReleaseStore store;

  /// Where the release is in it.
  final StoreState state;

  /// Where [state] came from.
  final StatusSource source;

  /// What the store said, as it said it (`IN_REVIEW`,
  /// `RELEASE_LIFECYCLE_STATE_PUBLISHED`).
  final String? detail;

  /// When the store was asked last, in UTC. The engine asks at most every
  /// ten minutes, unless the owner refreshes.
  final DateTime? checkedAt;

  /// When [state] last changed, in UTC.
  final DateTime? changedAt;

  /// Why the store could not be read the last time it was asked, or what the
  /// owner should know.
  final String? note;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$StoreStatusToJson(this);

  @override
  List<Object?> get props => [
    store,
    state,
    source,
    detail,
    checkedAt,
    changedAt,
    note,
  ];
}

/// One build of a release: the first, and every new build of the same
/// version after a rejection.
@JsonSerializable()
class ReleaseBuild extends Equatable {
  /// Creates a build.
  const new({
    required this.build,
    required this.runId,
    required this.createdAt,
  });

  /// Reads a build from its JSON form.
  factory ReleaseBuild.fromJson(Map<String, dynamic> json) =>
      _$ReleaseBuildFromJson(json);

  /// The build number (D-11).
  final int build;

  /// The run that builds and uploads it.
  final String runId;

  /// When the build was started, in UTC.
  final DateTime createdAt;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$ReleaseBuildToJson(this);

  @override
  List<Object?> get props => [build, runId, createdAt];
}

/// A release of one flavor of an app to the stores (D-17).
@JsonSerializable(explicitToJson: true, includeIfNull: false)
class Release extends Equatable {
  /// Creates a release.
  const new({
    required this.id,
    required this.projectId,
    required this.app,
    required this.flavor,
    required this.version,
    required this.build,
    required this.state,
    required this.stores,
    required this.builds,
    required this.mergeEnabled,
    required this.createdAt,
    required this.updatedAt,
    this.branch,
    this.baseBranch,
    this.tag,
    this.headSha,
    this.prNumber,
    this.prUrl,
    this.mergeCommit,
    this.mergeRunId,
    this.message,
  });

  /// Reads a release from its JSON form.
  factory Release.fromJson(Map<String, dynamic> json) =>
      _$ReleaseFromJson(json);

  /// The engine's id, for example `rel_1a2b3c4d5e6f7a8b`.
  final String id;

  /// The project.
  final String projectId;

  /// The app, by its path (`.` for the root).
  final String app;

  /// The flavor.
  final String flavor;

  /// The marketing version, `x.y.z`.
  final String version;

  /// The build number now: the last of [builds].
  final int build;

  /// Where the release is.
  final ReleaseState state;

  /// The status in each store the release targets.
  final List<StoreStatus> stores;

  /// Every build of the release, oldest first.
  final List<ReleaseBuild> builds;

  /// Whether `POST /releases/{id}/merge` is open: every store is live, the
  /// release has its pull request, and nothing merges it yet.
  final bool mergeEnabled;

  /// The release branch, `release/x.y.z`.
  final String? branch;

  /// The branch the release pull request merges into.
  final String? baseBranch;

  /// The tag of the current build, `v<x.y.z>+<build>`, once it is tagged.
  final String? tag;

  /// The commit the current build was tagged on, in full.
  final String? headSha;

  /// The number of the release pull request.
  final int? prNumber;

  /// Where to see the release pull request.
  final String? prUrl;

  /// The merge commit, once merged.
  final String? mergeCommit;

  /// The run that merges the pull request, once it was requested.
  final String? mergeRunId;

  /// Why the release was abandoned, or what the owner should know.
  final String? message;

  /// When the release was dispatched, in UTC.
  final DateTime createdAt;

  /// When it last changed, in UTC.
  final DateTime updatedAt;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$ReleaseToJson(this);

  @override
  List<Object?> get props => [
    id,
    projectId,
    app,
    flavor,
    version,
    build,
    state,
    stores,
    builds,
    mergeEnabled,
    branch,
    baseBranch,
    tag,
    headSha,
    prNumber,
    prUrl,
    mergeCommit,
    mergeRunId,
    message,
    createdAt,
    updatedAt,
  ];
}

/// The body of `GET /releases`.
@JsonSerializable(explicitToJson: true)
class ReleasesResponse extends Equatable {
  /// Creates a response.
  const new(this.releases);

  /// Reads a response from its JSON form.
  factory ReleasesResponse.fromJson(Map<String, dynamic> json) =>
      _$ReleasesResponseFromJson(json);

  /// The releases, newest first.
  final List<Release> releases;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$ReleasesResponseToJson(this);

  @override
  List<Object?> get props => [releases];
}

/// The body of `POST /releases/{id}/stores/{store}/status`: what the owner
/// says about a store (the buttons "Apple approved", "Apple live" and "Play:
/// live", for a store the engine cannot read).
@JsonSerializable(checked: true)
class StoreStatusRequest extends Equatable {
  /// Creates a request.
  const new({required this.state});

  /// Reads a request from its JSON form.
  factory StoreStatusRequest.fromJson(Map<String, dynamic> json) =>
      _$StoreStatusRequestFromJson(json);

  /// `approved` or `live` for Apple, `live` for Google Play.
  final StoreState state;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$StoreStatusRequestToJson(this);

  @override
  List<Object?> get props => [state];
}

/// The optional body of `POST /releases/{id}/abandon`.
@JsonSerializable(includeIfNull: false, checked: true)
class AbandonRequest extends Equatable {
  /// Creates a request.
  const new({this.reason});

  /// Reads a request from its JSON form.
  factory AbandonRequest.fromJson(Map<String, dynamic> json) =>
      _$AbandonRequestFromJson(json);

  /// Why, for the record.
  final String? reason;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$AbandonRequestToJson(this);

  @override
  List<Object?> get props => [reason];
}

/// A change to how a release reaches users once it is in the stores (U7a):
/// Apple's phased release (pause, resume, complete) and Google Play's staged
/// rollout (a new fraction, halt, complete). Each is a gated action (D-13).
@JsonEnum(valueField: 'wire')
enum RolloutAction {
  /// Apple: pause the phased release.
  pause('pause'),

  /// Apple: resume the paused phased release.
  resume('resume'),

  /// Both: release to every user now.
  complete('complete'),

  /// Google Play: stop the staged rollout where it is.
  halt('halt'),

  /// Google Play: roll out to [RolloutRequest.userFraction] of the users.
  fraction('fraction');

  new(this.wire);

  /// The name on the wire.
  final String wire;
}

/// The body of `POST /releases/{id}/rollout`.
@JsonSerializable(includeIfNull: false)
class RolloutRequest extends Equatable {
  /// Creates a request.
  const new({required this.store, required this.action, this.userFraction});

  /// Reads a request from its JSON form.
  factory RolloutRequest.fromJson(Map<String, dynamic> json) =>
      _$RolloutRequestFromJson(json);

  /// The store whose rollout changes.
  final ReleaseStore store;

  /// What changes.
  final RolloutAction action;

  /// For [RolloutAction.fraction]: the share of users, `0 < f ≤ 1`.
  final double? userFraction;

  /// Why the store cannot do [action], or `null` when it can.
  String? get problem => switch ((store, action)) {
    (ReleaseStore.apple, RolloutAction.halt || RolloutAction.fraction) =>
      'App Store Connect pauses, resumes or completes a phased release; it '
          'has no fraction to set.',
    (ReleaseStore.play, RolloutAction.pause || RolloutAction.resume) =>
      'Google Play halts a staged rollout or sets its fraction; it has no '
          'pause.',
    (_, RolloutAction.fraction)
        when userFraction == null || userFraction! <= 0 || userFraction! > 1 =>
      'Give the share of users as a fraction above 0 and at most 1.',
    _ => null,
  };

  /// The JSON form.
  Map<String, dynamic> toJson() => _$RolloutRequestToJson(this);

  @override
  List<Object?> get props => [store, action, userFraction];
}

// `json_serializable` cannot parse `factory .name` constructors yet.
// ignore_for_file: unnecessary_type_name_in_constructor

import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:xp_api/src/release.dart';

part 'release_history.g.dart';

/// What happened to a release, in its history (U7b).
@JsonEnum(valueField: 'wire')
enum ReleaseEventKind {
  /// The release was dispatched.
  created('created'),

  /// A build of it started.
  build('build'),

  /// Its status in a store changed.
  store('store'),

  /// The merge of its pull request was asked for.
  mergeRequested('merge_requested'),

  /// Its pull request was merged.
  merged('merged'),

  /// It was given up.
  abandoned('abandoned'),

  /// A change of its rollout in a store was asked for.
  rolloutRequested('rollout_requested'),

  /// Its rollout in a store changed.
  rollout('rollout'),

  /// A Shorebird patch of it was published.
  patch('patch'),

  /// The promotion or the rollback of a patch was asked for.
  patchRequested('patch_requested'),

  /// A patch went to the stable track.
  patchPromoted('patch_promoted'),

  /// A patch was rolled back.
  patchRolledBack('patch_rolled_back'),

  /// Its "What's new" or "What to test" text changed.
  texts('texts');

  new(this.wire);

  /// The name on the wire and in the database.
  final String wire;
}

/// One entry of the history of a release: what happened, when, and who did
/// it when a device did.
@JsonSerializable(includeIfNull: false)
class ReleaseEvent extends Equatable {
  /// Creates an entry.
  const new({
    required this.kind,
    required this.at,
    this.store,
    this.detail,
    this.by,
    this.runId,
    this.patchNumber,
  });

  /// Reads an entry from its JSON form.
  factory ReleaseEvent.fromJson(Map<String, dynamic> json) =>
      _$ReleaseEventFromJson(json);

  /// What happened.
  final ReleaseEventKind kind;

  /// When, in UTC.
  final DateTime at;

  /// The store it happened in, if one.
  final ReleaseStore? store;

  /// What it was, as the engine or the store said it: a store state, a
  /// rollout change, a build number.
  final String? detail;

  /// The name of the device that did it; `null` for the engine itself.
  final String? by;

  /// The run that does it, if one.
  final String? runId;

  /// The Shorebird patch, for the patch kinds.
  final int? patchNumber;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$ReleaseEventToJson(this);

  @override
  List<Object?> get props => [kind, at, store, detail, by, runId, patchNumber];
}

/// The body of `GET /releases/{id}/history`: oldest first.
@JsonSerializable(explicitToJson: true)
class ReleaseHistory extends Equatable {
  /// Creates the body.
  const new(this.events);

  /// Reads the body from its JSON form.
  factory ReleaseHistory.fromJson(Map<String, dynamic> json) =>
      _$ReleaseHistoryFromJson(json);

  /// What happened, oldest first.
  final List<ReleaseEvent> events;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$ReleaseHistoryToJson(this);

  @override
  List<Object?> get props => [events];
}

/// The body of `PUT /releases/{id}/texts`: the texts the uploads of the
/// release send to the stores. A missing or blank text is cleared.
@JsonSerializable(includeIfNull: false, checked: true)
class ReleaseTexts extends Equatable {
  /// Creates the body.
  const new({this.whatsNew, this.whatToTest});

  /// Reads the body from its JSON form.
  factory ReleaseTexts.fromJson(Map<String, dynamic> json) =>
      _$ReleaseTextsFromJson(json);

  /// What is new, for the store listing: Google Play's release notes.
  final String? whatsNew;

  /// What testers should try: Firebase App Distribution's release notes.
  final String? whatToTest;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$ReleaseTextsToJson(this);

  @override
  List<Object?> get props => [whatsNew, whatToTest];
}

/// What to do with a Shorebird patch of a release (U7b).
@JsonEnum(valueField: 'wire')
enum PatchAction {
  /// Move it to the stable track: every user gets it.
  promote('promote'),

  /// Roll it back: users go back to the patch before it, or the release.
  rollback('rollback');

  new(this.wire);

  /// The name on the wire and in the routes.
  final String wire;
}

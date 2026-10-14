// `json_serializable` cannot parse `factory .name` constructors yet.
// ignore_for_file: unnecessary_type_name_in_constructor

import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'release_notes.g.dart';

/// One commit in the notes of a release.
@JsonSerializable(includeIfNull: false)
class ReleaseNoteItem extends Equatable {
  /// Creates the item.
  const new({
    required this.sha,
    required this.description,
    this.scope,
    this.breaking = false,
  });

  /// Reads the item from its JSON form.
  factory ReleaseNoteItem.fromJson(Map<String, dynamic> json) =>
      _$ReleaseNoteItemFromJson(json);

  /// The commit, in full.
  final String sha;

  /// What the commit message says after `type(scope):`, or the whole subject
  /// of a commit that is not a conventional commit.
  final String description;

  /// The scope in parentheses, when there is one.
  final String? scope;

  /// Whether the commit says it breaks something (`!` or a `BREAKING CHANGE`
  /// footer).
  final bool breaking;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$ReleaseNoteItemToJson(this);

  @override
  List<Object?> get props => [sha, description, scope, breaking];
}

/// The commits of one conventional-commit type.
@JsonSerializable(explicitToJson: true)
class ReleaseNoteGroup extends Equatable {
  /// Creates the group.
  const new({required this.type, required this.title, required this.items});

  /// Reads the group from its JSON form.
  factory ReleaseNoteGroup.fromJson(Map<String, dynamic> json) =>
      _$ReleaseNoteGroupFromJson(json);

  /// The commit type: `feat`, `fix`, `perf`, `refactor`, `docs`, `other`, or
  /// `breaking` for the commits that break something.
  final String type;

  /// What the notes call the group, for example `Features`.
  final String title;

  /// The commits, newest first.
  final List<ReleaseNoteItem> items;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$ReleaseNoteGroupToJson(this);

  @override
  List<Object?> get props => [type, title, items];
}

/// The body of `GET /releases/{id}/notes`: what changed since the release
/// before it, as groups and as text ready to paste into Slack and WhatsApp.
@JsonSerializable(explicitToJson: true, includeIfNull: false)
class ReleaseNotes extends Equatable {
  /// Creates the notes.
  const new({
    required this.releaseId,
    required this.version,
    required this.build,
    required this.to,
    required this.commits,
    required this.groups,
    required this.slack,
    required this.whatsapp,
    this.from,
    this.compareUrl,
  });

  /// Reads the notes from their JSON form.
  factory ReleaseNotes.fromJson(Map<String, dynamic> json) =>
      _$ReleaseNotesFromJson(json);

  /// The release.
  final String releaseId;

  /// Its version, `x.y.z`.
  final String version;

  /// Its build number.
  final int build;

  /// The tag of the release before, when there is one. Without it the notes
  /// are the latest commits up to [to].
  final String? from;

  /// The commit the notes end at, in full.
  final String to;

  /// How many commits the notes cover (merge commits are left out).
  final int commits;

  /// The commits by type. Empty when nothing changed.
  final List<ReleaseNoteGroup> groups;

  /// A link to the comparison on GitHub, when there is a [from].
  final String? compareUrl;

  /// The notes as Slack `mrkdwn`.
  final String slack;

  /// The notes as WhatsApp text: `*bold*` and no link markup.
  final String whatsapp;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$ReleaseNotesToJson(this);

  @override
  List<Object?> get props => [
    releaseId,
    version,
    build,
    from,
    to,
    commits,
    groups,
    compareUrl,
    slack,
    whatsapp,
  ];
}

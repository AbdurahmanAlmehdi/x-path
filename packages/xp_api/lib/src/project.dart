// `json_serializable` cannot parse `factory .name` constructors yet.
// ignore_for_file: unnecessary_type_name_in_constructor

import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:xp_api/src/finding.dart';
import 'package:xp_api/src/project_profile.dart';

part 'project.g.dart';

/// A repository XPath releases, keyed by its source key (D-05, ADR 0015).
@JsonSerializable(explicitToJson: true, includeIfNull: false)
class Project extends Equatable {
  /// Creates a project.
  const new({
    required this.id,
    required this.host,
    required this.sourceKey,
    required this.fullName,
    required this.remote,
    required this.defaultBaseBranch,
    this.githubRepoId,
    this.localPath,
    this.profile = const ProjectProfile(),
    this.findings = const [],
    this.scannedAt,
  });

  /// Reads a project from its JSON form.
  factory Project.fromJson(Map<String, dynamic> json) =>
      _$ProjectFromJson(json);

  /// The [host] of a project on GitHub.
  static const githubHost = 'github.com';

  /// The engine's id for the project, for example `prj_1a2b3c4d5e6f7a8b`.
  final String id;

  /// Where the repository lives: [githubHost], another SSH host such as
  /// `bitbucket.org`, or `local` for a `file://` origin. An engine older
  /// than ADR 0015 sends none; its projects are all on GitHub.
  @JsonKey(defaultValue: githubHost)
  final String host;

  /// What keys the project's mirror and caches: the GitHub repository id in
  /// decimal, or `h` and 16 hex digits for another host. An engine older
  /// than ADR 0015 sends none; the GitHub repository id is the key then.
  @JsonKey(readValue: _readSourceKey)
  final String sourceKey;

  /// The id GitHub gave the repository, for a project on GitHub only. It
  /// survives renames and transfers.
  final int? githubRepoId;

  /// `owner/name`: as GitHub spells it, or the path of the remote on another
  /// host (which can have more than two segments).
  final String fullName;

  /// The URL the engine's mirror fetches from.
  final String remote;

  /// The folder the project was added from, when it was added by path. It
  /// only seeds scans (D-05); builds never use it.
  final String? localPath;

  /// The branch releases are based on (M6).
  final String defaultBaseBranch;

  /// What the last scan found, with the owner's edits applied.
  final ProjectProfile profile;

  /// What the last scan noticed.
  final List<Finding> findings;

  /// When the last scan ran, in UTC.
  final DateTime? scannedAt;

  /// Whether the repository is on GitHub, so GitHub steps can run for it.
  bool get isOnGitHub => host == githubHost;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$ProjectToJson(this);

  static Object? _readSourceKey(Map<dynamic, dynamic> json, String key) =>
      json[key] ?? json['githubRepoId']?.toString();

  @override
  List<Object?> get props => [
    id,
    host,
    sourceKey,
    githubRepoId,
    fullName,
    remote,
    localPath,
    defaultBaseBranch,
    profile,
    findings,
    scannedAt,
  ];
}

/// The body of `GET /projects`.
@JsonSerializable(explicitToJson: true)
class ProjectsResponse extends Equatable {
  /// Creates the list.
  const new(this.projects);

  /// Reads the list from its JSON form.
  factory ProjectsResponse.fromJson(Map<String, dynamic> json) =>
      _$ProjectsResponseFromJson(json);

  /// Every project, oldest first.
  final List<Project> projects;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$ProjectsResponseToJson(this);

  @override
  List<Object?> get props => [projects];
}

/// The body of `POST /projects`: exactly one of [path] and [remote], and
/// with [path] maybe the [sshUrl] the owner confirmed.
///
/// Reading a request from JSON fails with a `CheckedFromJsonException` for a
/// field of the wrong type.
@JsonSerializable(includeIfNull: false, checked: true)
class AddProjectRequest extends Equatable {
  /// Creates a request.
  const new({this.path, this.remote, this.sshUrl});

  /// Reads a request from its JSON form.
  factory AddProjectRequest.fromJson(Map<String, dynamic> json) =>
      _$AddProjectRequestFromJson(json);

  /// An absolute folder on the engine's machine that holds a clone. Its
  /// `origin` identifies the repository and its files seed the scan.
  final String? path;

  /// A GitHub repository (`owner/name`, or an HTTPS or SSH URL), or a
  /// repository on any other host by its SSH URL (scp-like or `ssh://`) or
  /// `file://` URL (ADR 0015).
  final String? remote;

  /// With [path]: the SSH URL to fetch from when the folder's `origin` is an
  /// HTTPS URL on a host other than GitHub. It is the URL the engine offered
  /// with `ssh_url_required`, which the owner confirmed; it must name the
  /// same repository. The folder's clone is not changed.
  final String? sshUrl;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$AddProjectRequestToJson(this);

  @override
  List<Object?> get props => [path, remote, sshUrl];
}

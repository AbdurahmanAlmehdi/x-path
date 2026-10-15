// `json_serializable` cannot parse `factory .name` constructors yet.
// ignore_for_file: unnecessary_type_name_in_constructor

import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:xp_api/src/credential.dart';

part 'github_token.g.dart';

/// The GitHub token of the engine, as `GET /github-token` shows it. The
/// engine has one, shared by every project; it adds projects, mirrors and
/// pushes with it. The token itself is never in the API.
@JsonSerializable(includeIfNull: false)
class GitHubTokenStatus extends Equatable {
  /// Creates the status.
  const new({
    required this.stored,
    this.status,
    this.login,
    this.message,
    this.fix,
  });

  /// Reads the status from its JSON form.
  factory GitHubTokenStatus.fromJson(Map<String, dynamic> json) =>
      _$GitHubTokenStatusFromJson(json);

  /// Whether the engine has a token.
  final bool stored;

  /// What GitHub said of the token just now (`GET /user`):
  /// [CredentialStatus.verified], [CredentialStatus.rejected] or
  /// [CredentialStatus.unreachable]. Absent without a token.
  final CredentialStatus? status;

  /// The GitHub login the token belongs to, when GitHub said.
  final String? login;

  /// Why the token was not accepted or could not be checked.
  final String? message;

  /// What to do about [message].
  final String? fix;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$GitHubTokenStatusToJson(this);

  @override
  List<Object?> get props => [stored, status, login, message, fix];
}

/// The body of `PUT /github-token`: a token for the engine (a personal
/// access token with the `repo` scope, or what `gh auth token` prints).
@JsonSerializable()
class SetGitHubTokenRequest extends Equatable {
  /// Creates the request.
  const new(this.token);

  /// Reads the request from its JSON form.
  factory SetGitHubTokenRequest.fromJson(Map<String, dynamic> json) =>
      _$SetGitHubTokenRequestFromJson(json);

  /// The token. Never logged or shown again.
  final String token;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$SetGitHubTokenRequestToJson(this);

  @override
  List<Object?> get props => [token];

  @override
  String toString() => 'SetGitHubTokenRequest(<token>)';
}

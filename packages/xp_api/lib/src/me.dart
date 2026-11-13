// `json_serializable` cannot parse `factory .name` constructors yet.
// ignore_for_file: unnecessary_type_name_in_constructor

import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:xp_api/src/device_token.dart';
import 'package:xp_api/src/person.dart';

part 'me.g.dart';

/// What a mutating action needs (ADR 0017). Reading needs nothing beyond a
/// token.
@JsonEnum(valueField: 'wire')
enum Permission {
  /// Dispatch, run again, cancel and resume, scan, run tests, edit
  /// workflows, pin artifacts.
  develop('develop', PersonRole.developer),

  /// Approve or deny any gate. Separate from [release] because a trigger
  /// may lower one gate to developers.
  decideApproval('decide_approval', PersonRole.releaser),

  /// Drive releases: merge, rollout, abandon, patch, texts, store refresh,
  /// turning a gate on.
  release('release', PersonRole.releaser),

  /// Change the engine: turning a gate off, projects, credentials,
  /// certificates, the GitHub token, runners, storage, the public URL,
  /// people and others' tokens.
  administer('administer', PersonRole.admin);

  new(this.wire, this.minimumRole);

  /// The name on the wire.
  final String wire;

  /// The lowest role that has the permission.
  final PersonRole minimumRole;
}

/// The body of `GET /me`: who the token that asks belongs to, and what it
/// may do (D16). A client hides what it may not do and never decides it
/// itself.
@JsonSerializable(explicitToJson: true)
class Me extends Equatable {
  /// Creates the answer.
  const new({
    required this.person,
    required this.token,
    required this.permissions,
  });

  /// Reads the answer from its JSON form.
  factory Me.fromJson(Map<String, dynamic> json) => _$MeFromJson(json);

  /// The person the token belongs to.
  final Person person;

  /// The token that asks.
  final TokenInfo token;

  /// What the token may do: the person's role and the token's kind together
  /// (an `mcp` token of an admin may only [Permission.develop]).
  final List<Permission> permissions;

  /// Whether the token has [permission].
  bool may(Permission permission) => permissions.contains(permission);

  /// The JSON form.
  Map<String, dynamic> toJson() => _$MeToJson(this);

  @override
  List<Object?> get props => [person, token, permissions];
}

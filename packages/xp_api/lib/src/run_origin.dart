// `json_serializable` cannot parse `factory .name` constructors yet.
// ignore_for_file: unnecessary_type_name_in_constructor

import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'run_origin.g.dart';

/// What started a run.
enum RunOriginKind {
  /// A person, from the app, `xp` or the web dashboard.
  person,

  /// An agent, through `xp mcp`, on behalf of a person.
  agent,
}

/// Who started a run (ADR 0017): the token that dispatched it and the
/// person it belongs to, kept as they were then.
@JsonSerializable(includeIfNull: false)
class RunOrigin extends Equatable {
  /// Creates the origin.
  const new({required this.kind, this.tokenId, this.personId, this.personName});

  /// Reads the origin from its JSON form.
  factory RunOrigin.fromJson(Map<String, dynamic> json) =>
      _$RunOriginFromJson(json);

  /// What started the run.
  final RunOriginKind kind;

  /// The device token that dispatched it, for example `tok_1a2b3c4d5e6f7a8b`.
  final String? tokenId;

  /// The person the token belongs to, for example `per_1a2b3c4d5e6f7a8b`.
  final String? personId;

  /// What the person was called when the run started. Kept after they are
  /// renamed or removed.
  final String? personName;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$RunOriginToJson(this);

  @override
  List<Object?> get props => [kind, tokenId, personId, personName];
}

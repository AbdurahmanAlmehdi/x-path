// `json_serializable` cannot parse `factory .name` constructors yet.
// ignore_for_file: unnecessary_type_name_in_constructor

import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:xp_api/src/device_token_kind.dart';

part 'device_token.g.dart';

/// The body of `POST /tokens`: a token for `xp` ([DeviceTokenKind.cli]) or
/// `xp mcp` ([DeviceTokenKind.mcp]), made from the app (U5b).
@JsonSerializable()
class CreateTokenRequest extends Equatable {
  /// Creates the request.
  const new({required this.name, required this.kind});

  /// Reads the request from its JSON form.
  factory CreateTokenRequest.fromJson(Map<String, dynamic> json) =>
      _$CreateTokenRequestFromJson(json);

  /// What the owner calls the client, for example `xp on MacBook`.
  final String name;

  /// What will use the token: `cli` or `mcp`.
  final DeviceTokenKind kind;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$CreateTokenRequestToJson(this);

  @override
  List<Object?> get props => [name, kind];
}

/// A device token as the engine describes it: never its secret.
@JsonSerializable()
class TokenInfo extends Equatable {
  /// Creates the description.
  const new({
    required this.id,
    required this.name,
    required this.kind,
    required this.createdAt,
  });

  /// Reads the description from its JSON form.
  factory TokenInfo.fromJson(Map<String, dynamic> json) =>
      _$TokenInfoFromJson(json);

  /// The engine's id, for example `tok_1a2b3c4d5e6f7a8b`.
  final String id;

  /// What the owner called it.
  final String name;

  /// What uses it.
  final DeviceTokenKind kind;

  /// When it was made.
  final DateTime createdAt;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$TokenInfoToJson(this);

  @override
  List<Object?> get props => [id, name, kind, createdAt];
}

/// The answer of `POST /tokens`: the token made, with its secret. The
/// secret is in this response only and never again.
@JsonSerializable(explicitToJson: true)
class CreatedToken extends Equatable {
  /// Creates the answer.
  const new({required this.info, required this.token});

  /// Reads the answer from its JSON form.
  factory CreatedToken.fromJson(Map<String, dynamic> json) =>
      _$CreatedTokenFromJson(json);

  /// The token made.
  final TokenInfo info;

  /// The bearer secret, `xpt_…`. Never logged.
  final String token;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$CreatedTokenToJson(this);

  @override
  List<Object?> get props => [info, token];

  @override
  String toString() => 'CreatedToken($info, <token>)';
}

/// The body of `GET /status`: what `xp status` shows of the engine beyond
/// its version, without asking GitHub or a store anything (U5b).
@JsonSerializable(explicitToJson: true)
class StatusResponse extends Equatable {
  /// Creates the response.
  const new({required this.token, required this.secretsLocked});

  /// Reads the response from its JSON form.
  factory StatusResponse.fromJson(Map<String, dynamic> json) =>
      _$StatusResponseFromJson(json);

  /// The token that asks.
  final TokenInfo token;

  /// Whether the engine could not reach its secrets at its last try (D-10):
  /// jobs that need them wait until they are unlocked.
  final bool secretsLocked;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$StatusResponseToJson(this);

  @override
  List<Object?> get props => [token, secretsLocked];
}

// `json_serializable` cannot parse `factory .name` constructors yet.
// ignore_for_file: unnecessary_type_name_in_constructor

import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'engine_check.g.dart';

/// How an [EngineCheck] came out, with the words of `xp runner doctor`.
@JsonEnum(valueField: 'wire')
enum CheckState {
  /// It holds.
  ok('ok'),

  /// It does not: see the detail and the fix.
  missing('missing'),

  /// It was not checked, or says nothing either way: see the detail.
  skipped('skipped');

  new(this.wire);

  /// The name on the wire.
  final String wire;
}

/// One thing the engine checked about itself (U5b): a capability of its own
/// runner, its secrets, its GitHub token, its credentials, or SSH to a git
/// host.
@JsonSerializable(includeIfNull: false)
class EngineCheck extends Equatable {
  /// Creates the check.
  const new({required this.name, required this.state, this.detail, this.fix});

  /// Reads the check from its JSON form.
  factory EngineCheck.fromJson(Map<String, dynamic> json) =>
      _$EngineCheckFromJson(json);

  /// What was checked, for example `android`, `secrets` or `ssh
  /// bitbucket.org`.
  final String name;

  /// How it came out.
  final CheckState state;

  /// What was found, one sentence without its full stop.
  final String? detail;

  /// What to do about it, one sentence without its full stop (UX-09: no
  /// HTTP path or CLI command).
  final String? fix;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$EngineCheckToJson(this);

  @override
  List<Object?> get props => [name, state, detail, fix];
}

/// The body of `GET /doctor`: what the engine found about the machine it
/// runs on, in the order it checked.
@JsonSerializable(explicitToJson: true)
class DoctorResponse extends Equatable {
  /// Creates the response.
  const new(this.checks);

  /// Reads the response from its JSON form.
  factory DoctorResponse.fromJson(Map<String, dynamic> json) =>
      _$DoctorResponseFromJson(json);

  /// The checks.
  final List<EngineCheck> checks;

  /// Whether nothing is [CheckState.missing].
  bool get healthy =>
      checks.every((check) => check.state != CheckState.missing);

  /// The JSON form.
  Map<String, dynamic> toJson() => _$DoctorResponseToJson(this);

  @override
  List<Object?> get props => [checks];
}

// `json_serializable` cannot parse `factory .name` constructors yet.
// ignore_for_file: unnecessary_type_name_in_constructor

import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'runner.g.dart';

/// Where a runner is (D-08).
@JsonEnum(valueField: 'wire')
enum RunnerStatus {
  /// No connection, or the engine has not finished probing it. It gets no
  /// jobs; the leases it holds run out 90 seconds after its last heartbeat.
  offline('offline'),

  /// Connected and probed: it gets jobs that fit its capabilities and slots.
  online('online'),

  /// Connected, finishing the jobs it holds, and asking for no more.
  draining('draining'),

  /// The owner revoked it. Its credential no longer works.
  revoked('revoked');

  new(this.wire);

  /// The name on the wire and in the database.
  final String wire;
}

/// A machine that runs jobs for the engine (D-08, D-19).
@JsonSerializable(includeIfNull: false)
class Runner extends Equatable {
  /// Creates a runner.
  const new({
    required this.id,
    required this.name,
    required this.status,
    required this.capabilities,
    required this.slots,
    required this.jobIds,
    required this.createdAt,
    this.os,
    this.arch,
    this.version,
    this.cores,
    this.lastHeartbeat,
    this.revokedAt,
  });

  /// Reads a runner from its JSON form.
  factory Runner.fromJson(Map<String, dynamic> json) => _$RunnerFromJson(json);

  /// The engine's id, for example `rnr_1a2b3c4d5e6f7a8b`.
  final String id;

  /// What the owner called it when they asked for the pairing token.
  final String name;

  /// Where it is.
  final RunnerStatus status;

  /// What the engine found it can do (`ios-sign`, `android`, `flutter`,
  /// `swift-linux`), from the probe it ran on the runner at its last
  /// connection, never from what the runner says about itself (D-19). Empty
  /// until the first probe.
  final List<String> capabilities;

  /// How many jobs it runs at once. `ios-sign` jobs run one at a time
  /// whatever this is.
  final int slots;

  /// The jobs it holds a lease for now.
  final List<String> jobIds;

  /// The operating system it reported, for example `macos`. Information
  /// only: capabilities come from the probe.
  final String? os;

  /// The processor architecture it reported, for example `arm64`.
  final String? arch;

  /// The `xp` version it reported.
  final String? version;

  /// The processor cores it reported; the default [slots] are a quarter of
  /// them.
  final int? cores;

  /// When the engine last heard from it, in UTC.
  final DateTime? lastHeartbeat;

  /// When it was paired, in UTC.
  final DateTime createdAt;

  /// When it was revoked, in UTC.
  final DateTime? revokedAt;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$RunnerToJson(this);

  @override
  List<Object?> get props => [
    id,
    name,
    status,
    capabilities,
    slots,
    jobIds,
    os,
    arch,
    version,
    cores,
    lastHeartbeat,
    createdAt,
    revokedAt,
  ];
}

/// The body of `GET /runners`.
@JsonSerializable(explicitToJson: true)
class RunnersResponse extends Equatable {
  /// Creates the list.
  const new(this.runners);

  /// Reads the list from its JSON form.
  factory RunnersResponse.fromJson(Map<String, dynamic> json) =>
      _$RunnersResponseFromJson(json);

  /// The runners, oldest first, revoked ones included.
  final List<Runner> runners;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$RunnersResponseToJson(this);

  @override
  List<Object?> get props => [runners];
}

/// The body of `POST /runners/pairing-tokens`.
@JsonSerializable(checked: true)
class CreatePairingTokenRequest extends Equatable {
  /// Creates a request.
  const new({required this.name});

  /// Reads a request from its JSON form.
  factory CreatePairingTokenRequest.fromJson(Map<String, dynamic> json) =>
      _$CreatePairingTokenRequestFromJson(json);

  /// The name of the runner the token pairs, for example `mac-mini`. Names
  /// are unique, revoked runners' too.
  final String name;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$CreatePairingTokenRequestToJson(this);

  @override
  List<Object?> get props => [name];
}

/// A pairing token (D-08): single use, valid for 15 minutes. It is shown
/// once and only its hash is kept.
@JsonSerializable()
class PairingToken extends Equatable {
  /// Creates a pairing token.
  const new({required this.token, required this.name, required this.expiresAt});

  /// Reads a pairing token from its JSON form.
  factory PairingToken.fromJson(Map<String, dynamic> json) =>
      _$PairingTokenFromJson(json);

  /// The secret, `xpp_` followed by 43 URL-safe characters.
  final String token;

  /// The name of the runner it pairs.
  final String name;

  /// When it stops working, in UTC.
  final DateTime expiresAt;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$PairingTokenToJson(this);

  @override
  List<Object?> get props => [token, name, expiresAt];
}

/// The body of `POST /runners/pair`.
@JsonSerializable(checked: true)
class PairRunnerRequest extends Equatable {
  /// Creates a request.
  const new({required this.pairingToken});

  /// Reads a request from its JSON form.
  factory PairRunnerRequest.fromJson(Map<String, dynamic> json) =>
      _$PairRunnerRequestFromJson(json);

  /// The pairing token the owner created.
  final String pairingToken;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$PairRunnerRequestToJson(this);

  @override
  List<Object?> get props => [pairingToken];
}

/// The answer of `POST /runners/pair`: the runner and its credential.
@JsonSerializable(explicitToJson: true)
class PairRunnerResponse extends Equatable {
  /// Creates the answer.
  const new({required this.runner, required this.token});

  /// Reads the answer from its JSON form.
  factory PairRunnerResponse.fromJson(Map<String, dynamic> json) =>
      _$PairRunnerResponseFromJson(json);

  /// The runner that was paired.
  final Runner runner;

  /// The runner's credential: a device token of kind `runner`. It is shown
  /// once and only its hash is kept.
  final String token;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$PairRunnerResponseToJson(this);

  @override
  List<Object?> get props => [runner, token];
}

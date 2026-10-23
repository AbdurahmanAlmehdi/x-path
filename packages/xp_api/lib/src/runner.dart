// `json_serializable` cannot parse `factory .name` constructors yet.
// ignore_for_file: unnecessary_type_name_in_constructor

import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:xp_api/src/runner_protocol.dart';

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
@JsonSerializable(includeIfNull: false, explicitToJson: true)
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
    this.missing,
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

  /// What it cannot do, why, and what gives it, from the same probe as
  /// [capabilities]. Kept in memory only: present while it is connected.
  final List<MissingCapability>? missing;

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
    missing,
  ];
}

/// What a runner is doing, as the app and the CLI show it.
enum RunnerActivity {
  /// Online and running no job.
  idle,

  /// Online and running jobs.
  busy,

  /// Finishing its jobs and taking no new one, before an update.
  updating,

  /// Offline while it still holds the leases of jobs: lost mid-job.
  lost,

  /// Offline.
  offline,

  /// Revoked by the owner.
  revoked,
}

/// What [Runner.status] and its jobs mean for the owner.
extension RunnerActivityOf on Runner {
  /// What the runner is doing.
  RunnerActivity get activity => switch (status) {
    RunnerStatus.online when jobIds.isEmpty => RunnerActivity.idle,
    RunnerStatus.online => RunnerActivity.busy,
    RunnerStatus.draining => RunnerActivity.updating,
    RunnerStatus.offline when jobIds.isNotEmpty => RunnerActivity.lost,
    RunnerStatus.offline => RunnerActivity.offline,
    RunnerStatus.revoked => RunnerActivity.revoked,
  };
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
@JsonSerializable(includeIfNull: false)
class PairingToken extends Equatable {
  /// Creates a pairing token.
  const new({
    required this.token,
    required this.name,
    required this.expiresAt,
    this.engineUrl,
  });

  /// Reads a pairing token from its JSON form.
  factory PairingToken.fromJson(Map<String, dynamic> json) =>
      _$PairingTokenFromJson(json);

  /// The secret, `xpp_` followed by 43 URL-safe characters.
  final String token;

  /// The name of the runner it pairs.
  final String name;

  /// When it stops working, in UTC.
  final DateTime expiresAt;

  /// The address runners reach the engine at (the runner URL the owner set),
  /// for the `xp runner pair --engine` command; `null` when none is set.
  final String? engineUrl;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$PairingTokenToJson(this);

  @override
  List<Object?> get props => [token, name, expiresAt, engineUrl];
}

/// The address runners reach the engine at: the body of `GET` and `PUT
/// /settings/runner-url`.
@JsonSerializable(includeIfNull: false)
class RunnerUrl extends Equatable {
  /// Creates the setting.
  const new({this.url, this.warning});

  /// Reads the setting from its JSON form.
  factory RunnerUrl.fromJson(Map<String, dynamic> json) =>
      _$RunnerUrlFromJson(json);

  /// The absolute `http` or `https` URL, or `null` when none is set.
  final String? url;

  /// Why the URL may be a bad idea though it was accepted, for example a
  /// plain `http` URL that leaves this network; one sentence.
  final String? warning;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$RunnerUrlToJson(this);

  @override
  List<Object?> get props => [url, warning];
}

/// The body of `PUT /settings/runner-url`.
@JsonSerializable(checked: true)
class SetRunnerUrlRequest extends Equatable {
  /// Creates a request; a `null` [url] clears the setting.
  const new({required this.url});

  /// Reads a request from its JSON form.
  factory SetRunnerUrlRequest.fromJson(Map<String, dynamic> json) =>
      _$SetRunnerUrlRequestFromJson(json);

  /// The runner URL, or `null` to clear it. The key must be there.
  @JsonKey(required: true)
  final String? url;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$SetRunnerUrlRequestToJson(this);

  @override
  List<Object?> get props => [url];
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

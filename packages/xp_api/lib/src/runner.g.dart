// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'runner.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Runner _$RunnerFromJson(Map<String, dynamic> json) => Runner(
  id: json['id'] as String,
  name: json['name'] as String,
  status: $enumDecode(_$RunnerStatusEnumMap, json['status']),
  capabilities: (json['capabilities'] as List<dynamic>)
      .map((e) => e as String)
      .toList(),
  slots: (json['slots'] as num).toInt(),
  jobIds: (json['jobIds'] as List<dynamic>).map((e) => e as String).toList(),
  createdAt: DateTime.parse(json['createdAt'] as String),
  os: json['os'] as String?,
  arch: json['arch'] as String?,
  version: json['version'] as String?,
  cores: (json['cores'] as num?)?.toInt(),
  lastHeartbeat: json['lastHeartbeat'] == null
      ? null
      : DateTime.parse(json['lastHeartbeat'] as String),
  revokedAt: json['revokedAt'] == null
      ? null
      : DateTime.parse(json['revokedAt'] as String),
);

Map<String, dynamic> _$RunnerToJson(Runner instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'status': _$RunnerStatusEnumMap[instance.status]!,
  'capabilities': instance.capabilities,
  'slots': instance.slots,
  'jobIds': instance.jobIds,
  'os': ?instance.os,
  'arch': ?instance.arch,
  'version': ?instance.version,
  'cores': ?instance.cores,
  'lastHeartbeat': ?instance.lastHeartbeat?.toIso8601String(),
  'createdAt': instance.createdAt.toIso8601String(),
  'revokedAt': ?instance.revokedAt?.toIso8601String(),
};

const _$RunnerStatusEnumMap = {
  RunnerStatus.offline: 'offline',
  RunnerStatus.online: 'online',
  RunnerStatus.draining: 'draining',
  RunnerStatus.revoked: 'revoked',
};

RunnersResponse _$RunnersResponseFromJson(Map<String, dynamic> json) =>
    RunnersResponse(
      (json['runners'] as List<dynamic>)
          .map((e) => Runner.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$RunnersResponseToJson(RunnersResponse instance) =>
    <String, dynamic>{
      'runners': instance.runners.map((e) => e.toJson()).toList(),
    };

CreatePairingTokenRequest _$CreatePairingTokenRequestFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('CreatePairingTokenRequest', json, ($checkedConvert) {
  final val = CreatePairingTokenRequest(
    name: $checkedConvert('name', (v) => v as String),
  );
  return val;
});

Map<String, dynamic> _$CreatePairingTokenRequestToJson(
  CreatePairingTokenRequest instance,
) => <String, dynamic>{'name': instance.name};

PairingToken _$PairingTokenFromJson(Map<String, dynamic> json) => PairingToken(
  token: json['token'] as String,
  name: json['name'] as String,
  expiresAt: DateTime.parse(json['expiresAt'] as String),
);

Map<String, dynamic> _$PairingTokenToJson(PairingToken instance) =>
    <String, dynamic>{
      'token': instance.token,
      'name': instance.name,
      'expiresAt': instance.expiresAt.toIso8601String(),
    };

PairRunnerRequest _$PairRunnerRequestFromJson(Map<String, dynamic> json) =>
    $checkedCreate('PairRunnerRequest', json, ($checkedConvert) {
      final val = PairRunnerRequest(
        pairingToken: $checkedConvert('pairingToken', (v) => v as String),
      );
      return val;
    });

Map<String, dynamic> _$PairRunnerRequestToJson(PairRunnerRequest instance) =>
    <String, dynamic>{'pairingToken': instance.pairingToken};

PairRunnerResponse _$PairRunnerResponseFromJson(Map<String, dynamic> json) =>
    PairRunnerResponse(
      runner: Runner.fromJson(json['runner'] as Map<String, dynamic>),
      token: json['token'] as String,
    );

Map<String, dynamic> _$PairRunnerResponseToJson(PairRunnerResponse instance) =>
    <String, dynamic>{
      'runner': instance.runner.toJson(),
      'token': instance.token,
    };

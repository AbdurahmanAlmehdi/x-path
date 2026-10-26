// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device_token.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CreateTokenRequest _$CreateTokenRequestFromJson(Map<String, dynamic> json) =>
    CreateTokenRequest(
      name: json['name'] as String,
      kind: $enumDecode(_$DeviceTokenKindEnumMap, json['kind']),
    );

Map<String, dynamic> _$CreateTokenRequestToJson(CreateTokenRequest instance) =>
    <String, dynamic>{
      'name': instance.name,
      'kind': _$DeviceTokenKindEnumMap[instance.kind]!,
    };

const _$DeviceTokenKindEnumMap = {
  DeviceTokenKind.app: 'app',
  DeviceTokenKind.cli: 'cli',
  DeviceTokenKind.mcp: 'mcp',
  DeviceTokenKind.runner: 'runner',
};

TokenInfo _$TokenInfoFromJson(Map<String, dynamic> json) => TokenInfo(
  id: json['id'] as String,
  name: json['name'] as String,
  kind: $enumDecode(_$DeviceTokenKindEnumMap, json['kind']),
  createdAt: DateTime.parse(json['createdAt'] as String),
);

Map<String, dynamic> _$TokenInfoToJson(TokenInfo instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'kind': _$DeviceTokenKindEnumMap[instance.kind]!,
  'createdAt': instance.createdAt.toIso8601String(),
};

CreatedToken _$CreatedTokenFromJson(Map<String, dynamic> json) => CreatedToken(
  info: TokenInfo.fromJson(json['info'] as Map<String, dynamic>),
  token: json['token'] as String,
);

Map<String, dynamic> _$CreatedTokenToJson(CreatedToken instance) =>
    <String, dynamic>{'info': instance.info.toJson(), 'token': instance.token};

StatusResponse _$StatusResponseFromJson(Map<String, dynamic> json) =>
    StatusResponse(
      token: TokenInfo.fromJson(json['token'] as Map<String, dynamic>),
      secretsLocked: json['secretsLocked'] as bool,
    );

Map<String, dynamic> _$StatusResponseToJson(StatusResponse instance) =>
    <String, dynamic>{
      'token': instance.token.toJson(),
      'secretsLocked': instance.secretsLocked,
    };

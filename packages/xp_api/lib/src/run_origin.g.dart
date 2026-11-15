// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'run_origin.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

RunOrigin _$RunOriginFromJson(Map<String, dynamic> json) => RunOrigin(
  kind: $enumDecode(_$RunOriginKindEnumMap, json['kind']),
  tokenId: json['tokenId'] as String?,
  personId: json['personId'] as String?,
  personName: json['personName'] as String?,
);

Map<String, dynamic> _$RunOriginToJson(RunOrigin instance) => <String, dynamic>{
  'kind': _$RunOriginKindEnumMap[instance.kind]!,
  'tokenId': ?instance.tokenId,
  'personId': ?instance.personId,
  'personName': ?instance.personName,
};

const _$RunOriginKindEnumMap = {
  RunOriginKind.person: 'person',
  RunOriginKind.agent: 'agent',
};

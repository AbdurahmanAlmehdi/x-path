// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'engine_check.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

EngineCheck _$EngineCheckFromJson(Map<String, dynamic> json) => EngineCheck(
  name: json['name'] as String,
  state: $enumDecode(_$CheckStateEnumMap, json['state']),
  detail: json['detail'] as String?,
  fix: json['fix'] as String?,
);

Map<String, dynamic> _$EngineCheckToJson(EngineCheck instance) =>
    <String, dynamic>{
      'name': instance.name,
      'state': _$CheckStateEnumMap[instance.state]!,
      'detail': ?instance.detail,
      'fix': ?instance.fix,
    };

const _$CheckStateEnumMap = {
  CheckState.ok: 'ok',
  CheckState.missing: 'missing',
  CheckState.skipped: 'skipped',
};

DoctorResponse _$DoctorResponseFromJson(Map<String, dynamic> json) =>
    DoctorResponse(
      (json['checks'] as List<dynamic>)
          .map((e) => EngineCheck.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$DoctorResponseToJson(DoctorResponse instance) =>
    <String, dynamic>{
      'checks': instance.checks.map((e) => e.toJson()).toList(),
    };

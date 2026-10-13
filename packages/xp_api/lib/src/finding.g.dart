// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'finding.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Finding _$FindingFromJson(Map<String, dynamic> json) => Finding(
  severity: $enumDecode(_$FindingSeverityEnumMap, json['severity']),
  code: json['code'] as String,
  message: json['message'] as String,
  fix: json['fix'] as String,
  path: json['path'] as String?,
  app: json['app'] as String?,
  flavor: json['flavor'] as String?,
);

Map<String, dynamic> _$FindingToJson(Finding instance) => <String, dynamic>{
  'severity': _$FindingSeverityEnumMap[instance.severity]!,
  'code': instance.code,
  'message': instance.message,
  'fix': instance.fix,
  'path': ?instance.path,
  'app': ?instance.app,
  'flavor': ?instance.flavor,
};

const _$FindingSeverityEnumMap = {
  FindingSeverity.error: 'error',
  FindingSeverity.warning: 'warning',
  FindingSeverity.info: 'info',
};

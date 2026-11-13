// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'person.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Person _$PersonFromJson(Map<String, dynamic> json) => Person(
  id: json['id'] as String,
  name: json['name'] as String,
  role: $enumDecode(_$PersonRoleEnumMap, json['role']),
  createdAt: DateTime.parse(json['createdAt'] as String),
  removedAt: json['removedAt'] == null
      ? null
      : DateTime.parse(json['removedAt'] as String),
);

Map<String, dynamic> _$PersonToJson(Person instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'role': _$PersonRoleEnumMap[instance.role]!,
  'createdAt': instance.createdAt.toIso8601String(),
  'removedAt': ?instance.removedAt?.toIso8601String(),
};

const _$PersonRoleEnumMap = {
  PersonRole.viewer: 'viewer',
  PersonRole.developer: 'developer',
  PersonRole.releaser: 'releaser',
  PersonRole.admin: 'admin',
};

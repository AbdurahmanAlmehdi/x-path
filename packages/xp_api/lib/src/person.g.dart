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

PeopleResponse _$PeopleResponseFromJson(Map<String, dynamic> json) =>
    PeopleResponse(
      (json['people'] as List<dynamic>)
          .map((e) => Person.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$PeopleResponseToJson(PeopleResponse instance) =>
    <String, dynamic>{
      'people': instance.people.map((e) => e.toJson()).toList(),
    };

CreatePersonRequest _$CreatePersonRequestFromJson(Map<String, dynamic> json) =>
    $checkedCreate('CreatePersonRequest', json, ($checkedConvert) {
      final val = CreatePersonRequest(
        name: $checkedConvert('name', (v) => v as String),
        role: $checkedConvert(
          'role',
          (v) => $enumDecode(_$PersonRoleEnumMap, v),
        ),
      );
      return val;
    });

Map<String, dynamic> _$CreatePersonRequestToJson(
  CreatePersonRequest instance,
) => <String, dynamic>{
  'name': instance.name,
  'role': _$PersonRoleEnumMap[instance.role]!,
};

UpdatePersonRequest _$UpdatePersonRequestFromJson(Map<String, dynamic> json) =>
    $checkedCreate('UpdatePersonRequest', json, ($checkedConvert) {
      final val = UpdatePersonRequest(
        name: $checkedConvert('name', (v) => v as String?),
        role: $checkedConvert(
          'role',
          (v) => $enumDecodeNullable(_$PersonRoleEnumMap, v),
        ),
      );
      return val;
    });

Map<String, dynamic> _$UpdatePersonRequestToJson(
  UpdatePersonRequest instance,
) => <String, dynamic>{
  'name': ?instance.name,
  'role': ?_$PersonRoleEnumMap[instance.role],
};

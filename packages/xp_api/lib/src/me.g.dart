// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'me.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Me _$MeFromJson(Map<String, dynamic> json) => Me(
  person: Person.fromJson(json['person'] as Map<String, dynamic>),
  token: TokenInfo.fromJson(json['token'] as Map<String, dynamic>),
  permissions: (json['permissions'] as List<dynamic>)
      .map((e) => $enumDecode(_$PermissionEnumMap, e))
      .toList(),
);

Map<String, dynamic> _$MeToJson(Me instance) => <String, dynamic>{
  'person': instance.person.toJson(),
  'token': instance.token.toJson(),
  'permissions': instance.permissions
      .map((e) => _$PermissionEnumMap[e]!)
      .toList(),
};

const _$PermissionEnumMap = {
  Permission.develop: 'develop',
  Permission.decideApproval: 'decide_approval',
  Permission.release: 'release',
  Permission.administer: 'administer',
};

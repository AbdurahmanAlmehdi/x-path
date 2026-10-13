// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'credential.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Credential _$CredentialFromJson(Map<String, dynamic> json) => Credential(
  id: json['id'] as String,
  projectId: json['projectId'] as String,
  app: json['app'] as String,
  flavor: json['flavor'] as String,
  kind: $enumDecode(_$CredentialKindEnumMap, json['kind']),
  status: $enumDecode(_$CredentialStatusEnumMap, json['status']),
  account: json['account'] as String?,
  verifiedAt: json['verifiedAt'] == null
      ? null
      : DateTime.parse(json['verifiedAt'] as String),
  checkedAt: json['checkedAt'] == null
      ? null
      : DateTime.parse(json['checkedAt'] as String),
  message: json['message'] as String?,
  fix: json['fix'] as String?,
);

Map<String, dynamic> _$CredentialToJson(Credential instance) =>
    <String, dynamic>{
      'id': instance.id,
      'projectId': instance.projectId,
      'app': instance.app,
      'flavor': instance.flavor,
      'kind': _$CredentialKindEnumMap[instance.kind]!,
      'status': _$CredentialStatusEnumMap[instance.status]!,
      'account': ?instance.account,
      'verifiedAt': ?instance.verifiedAt?.toIso8601String(),
      'checkedAt': ?instance.checkedAt?.toIso8601String(),
      'message': ?instance.message,
      'fix': ?instance.fix,
    };

const _$CredentialKindEnumMap = {
  CredentialKind.ascKey: 'asc_key',
  CredentialKind.appleId: 'apple_id',
  CredentialKind.playSa: 'play_sa',
  CredentialKind.firebaseSa: 'firebase_sa',
  CredentialKind.keystore: 'keystore',
  CredentialKind.shorebird: 'shorebird',
  CredentialKind.github: 'github',
  CredentialKind.slack: 'slack',
};

const _$CredentialStatusEnumMap = {
  CredentialStatus.unverified: 'unverified',
  CredentialStatus.verified: 'verified',
  CredentialStatus.rejected: 'rejected',
  CredentialStatus.unreachable: 'unreachable',
};

CredentialsResponse _$CredentialsResponseFromJson(Map<String, dynamic> json) =>
    CredentialsResponse(
      (json['credentials'] as List<dynamic>)
          .map((e) => Credential.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$CredentialsResponseToJson(
  CredentialsResponse instance,
) => <String, dynamic>{
  'credentials': instance.credentials.map((e) => e.toJson()).toList(),
};

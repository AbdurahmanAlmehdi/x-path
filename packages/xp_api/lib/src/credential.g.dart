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
  name: json['name'] as String?,
  account: json['account'] as String?,
  verifiedAt: json['verifiedAt'] == null
      ? null
      : DateTime.parse(json['verifiedAt'] as String),
  checkedAt: json['checkedAt'] == null
      ? null
      : DateTime.parse(json['checkedAt'] as String),
  message: json['message'] as String?,
  fix: json['fix'] as String?,
  credentialStatus: $enumDecodeNullable(
    _$CredentialStatusEnumMap,
    json['credentialStatus'],
  ),
  assignmentStatus: $enumDecodeNullable(
    _$CredentialStatusEnumMap,
    json['assignmentStatus'],
  ),
);

Map<String, dynamic> _$CredentialToJson(Credential instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': ?instance.name,
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
      'credentialStatus': ?_$CredentialStatusEnumMap[instance.credentialStatus],
      'assignmentStatus': ?_$CredentialStatusEnumMap[instance.assignmentStatus],
    };

const _$CredentialKindEnumMap = {
  CredentialKind.ascKey: 'asc_key',
  CredentialKind.appleId: 'apple_id',
  CredentialKind.appleDistribution: 'apple_distribution',
  CredentialKind.playSa: 'play_sa',
  CredentialKind.firebaseSa: 'firebase_sa',
  CredentialKind.keystore: 'keystore',
  CredentialKind.dartDefines: 'dart_defines',
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

CredentialUsage _$CredentialUsageFromJson(Map<String, dynamic> json) =>
    CredentialUsage(
      projectId: json['projectId'] as String,
      app: json['app'] as String,
      flavor: json['flavor'] as String,
      status: $enumDecode(_$CredentialStatusEnumMap, json['status']),
      project: json['project'] as String?,
      verifiedAt: json['verifiedAt'] == null
          ? null
          : DateTime.parse(json['verifiedAt'] as String),
      checkedAt: json['checkedAt'] == null
          ? null
          : DateTime.parse(json['checkedAt'] as String),
      message: json['message'] as String?,
      fix: json['fix'] as String?,
    );

Map<String, dynamic> _$CredentialUsageToJson(CredentialUsage instance) =>
    <String, dynamic>{
      'projectId': instance.projectId,
      'project': ?instance.project,
      'app': instance.app,
      'flavor': instance.flavor,
      'status': _$CredentialStatusEnumMap[instance.status]!,
      'verifiedAt': ?instance.verifiedAt?.toIso8601String(),
      'checkedAt': ?instance.checkedAt?.toIso8601String(),
      'message': ?instance.message,
      'fix': ?instance.fix,
    };

NamedCredential _$NamedCredentialFromJson(Map<String, dynamic> json) =>
    NamedCredential(
      id: json['id'] as String,
      name: json['name'] as String,
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
      usedBy:
          (json['usedBy'] as List<dynamic>?)
              ?.map((e) => CredentialUsage.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );

Map<String, dynamic> _$NamedCredentialToJson(NamedCredential instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'kind': _$CredentialKindEnumMap[instance.kind]!,
      'status': _$CredentialStatusEnumMap[instance.status]!,
      'account': ?instance.account,
      'verifiedAt': ?instance.verifiedAt?.toIso8601String(),
      'checkedAt': ?instance.checkedAt?.toIso8601String(),
      'message': ?instance.message,
      'fix': ?instance.fix,
      'usedBy': instance.usedBy.map((e) => e.toJson()).toList(),
    };

NamedCredentialsResponse _$NamedCredentialsResponseFromJson(
  Map<String, dynamic> json,
) => NamedCredentialsResponse(
  (json['credentials'] as List<dynamic>)
      .map((e) => NamedCredential.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$NamedCredentialsResponseToJson(
  NamedCredentialsResponse instance,
) => <String, dynamic>{
  'credentials': instance.credentials.map((e) => e.toJson()).toList(),
};

AssignCredentialRequest _$AssignCredentialRequestFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('AssignCredentialRequest', json, ($checkedConvert) {
  final val = AssignCredentialRequest(
    credentialId: $checkedConvert('credentialId', (v) => v as String),
    allFlavors: $checkedConvert('allFlavors', (v) => v as bool? ?? false),
    replace: $checkedConvert('replace', (v) => v as bool? ?? false),
  );
  return val;
});

Map<String, dynamic> _$AssignCredentialRequestToJson(
  AssignCredentialRequest instance,
) => <String, dynamic>{
  'credentialId': instance.credentialId,
  'allFlavors': instance.allFlavors,
  'replace': instance.replace,
};

AssignCredentialResponse _$AssignCredentialResponseFromJson(
  Map<String, dynamic> json,
) => AssignCredentialResponse(
  assigned: (json['assigned'] as List<dynamic>)
      .map((e) => Credential.fromJson(e as Map<String, dynamic>))
      .toList(),
  kept:
      (json['kept'] as List<dynamic>?)
          ?.map((e) => Credential.fromJson(e as Map<String, dynamic>))
          .toList() ??
      [],
);

Map<String, dynamic> _$AssignCredentialResponseToJson(
  AssignCredentialResponse instance,
) => <String, dynamic>{
  'assigned': instance.assigned.map((e) => e.toJson()).toList(),
  'kept': instance.kept.map((e) => e.toJson()).toList(),
};

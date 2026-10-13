// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'artifact.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Artifact _$ArtifactFromJson(Map<String, dynamic> json) => Artifact(
  id: json['id'] as String,
  jobId: json['jobId'] as String,
  kind: $enumDecode(_$ArtifactKindEnumMap, json['kind']),
  name: json['name'] as String,
  size: (json['size'] as num).toInt(),
  sha256: json['sha256'] as String,
  pinned: json['pinned'] as bool,
  createdAt: DateTime.parse(json['createdAt'] as String),
);

Map<String, dynamic> _$ArtifactToJson(Artifact instance) => <String, dynamic>{
  'id': instance.id,
  'jobId': instance.jobId,
  'kind': _$ArtifactKindEnumMap[instance.kind]!,
  'name': instance.name,
  'size': instance.size,
  'sha256': instance.sha256,
  'pinned': instance.pinned,
  'createdAt': instance.createdAt.toIso8601String(),
};

const _$ArtifactKindEnumMap = {
  ArtifactKind.ipa: 'ipa',
  ArtifactKind.aab: 'aab',
  ArtifactKind.apk: 'apk',
  ArtifactKind.mapping: 'mapping',
  ArtifactKind.dsym: 'dsym',
  ArtifactKind.manifest: 'manifest',
  ArtifactKind.shorebirdSymbols: 'shorebird_symbols',
};

ArtifactsResponse _$ArtifactsResponseFromJson(Map<String, dynamic> json) =>
    ArtifactsResponse(
      (json['artifacts'] as List<dynamic>)
          .map((e) => Artifact.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$ArtifactsResponseToJson(ArtifactsResponse instance) =>
    <String, dynamic>{
      'artifacts': instance.artifacts.map((e) => e.toJson()).toList(),
    };

// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'project.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Project _$ProjectFromJson(Map<String, dynamic> json) => Project(
  id: json['id'] as String,
  host: json['host'] as String? ?? 'github.com',
  sourceKey: Project._readSourceKey(json, 'sourceKey') as String,
  fullName: json['fullName'] as String,
  remote: json['remote'] as String,
  defaultBaseBranch: json['defaultBaseBranch'] as String,
  githubRepoId: (json['githubRepoId'] as num?)?.toInt(),
  localPath: json['localPath'] as String?,
  profile: json['profile'] == null
      ? const ProjectProfile()
      : ProjectProfile.fromJson(json['profile'] as Map<String, dynamic>),
  findings:
      (json['findings'] as List<dynamic>?)
          ?.map((e) => Finding.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
  scannedAt: json['scannedAt'] == null
      ? null
      : DateTime.parse(json['scannedAt'] as String),
);

Map<String, dynamic> _$ProjectToJson(Project instance) => <String, dynamic>{
  'id': instance.id,
  'host': instance.host,
  'sourceKey': instance.sourceKey,
  'githubRepoId': ?instance.githubRepoId,
  'fullName': instance.fullName,
  'remote': instance.remote,
  'localPath': ?instance.localPath,
  'defaultBaseBranch': instance.defaultBaseBranch,
  'profile': instance.profile.toJson(),
  'findings': instance.findings.map((e) => e.toJson()).toList(),
  'scannedAt': ?instance.scannedAt?.toIso8601String(),
};

ProjectsResponse _$ProjectsResponseFromJson(Map<String, dynamic> json) =>
    ProjectsResponse(
      (json['projects'] as List<dynamic>)
          .map((e) => Project.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$ProjectsResponseToJson(ProjectsResponse instance) =>
    <String, dynamic>{
      'projects': instance.projects.map((e) => e.toJson()).toList(),
    };

AddProjectRequest _$AddProjectRequestFromJson(Map<String, dynamic> json) =>
    $checkedCreate('AddProjectRequest', json, ($checkedConvert) {
      final val = AddProjectRequest(
        path: $checkedConvert('path', (v) => v as String?),
        remote: $checkedConvert('remote', (v) => v as String?),
        sshUrl: $checkedConvert('sshUrl', (v) => v as String?),
      );
      return val;
    });

Map<String, dynamic> _$AddProjectRequestToJson(AddProjectRequest instance) =>
    <String, dynamic>{
      'path': ?instance.path,
      'remote': ?instance.remote,
      'sshUrl': ?instance.sshUrl,
    };

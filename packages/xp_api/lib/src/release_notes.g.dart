// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'release_notes.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ReleaseNoteItem _$ReleaseNoteItemFromJson(Map<String, dynamic> json) =>
    ReleaseNoteItem(
      sha: json['sha'] as String,
      description: json['description'] as String,
      scope: json['scope'] as String?,
      breaking: json['breaking'] as bool? ?? false,
    );

Map<String, dynamic> _$ReleaseNoteItemToJson(ReleaseNoteItem instance) =>
    <String, dynamic>{
      'sha': instance.sha,
      'description': instance.description,
      'scope': ?instance.scope,
      'breaking': instance.breaking,
    };

ReleaseNoteGroup _$ReleaseNoteGroupFromJson(Map<String, dynamic> json) =>
    ReleaseNoteGroup(
      type: json['type'] as String,
      title: json['title'] as String,
      items: (json['items'] as List<dynamic>)
          .map((e) => ReleaseNoteItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$ReleaseNoteGroupToJson(ReleaseNoteGroup instance) =>
    <String, dynamic>{
      'type': instance.type,
      'title': instance.title,
      'items': instance.items.map((e) => e.toJson()).toList(),
    };

ReleaseNotes _$ReleaseNotesFromJson(Map<String, dynamic> json) => ReleaseNotes(
  releaseId: json['releaseId'] as String,
  version: json['version'] as String,
  build: (json['build'] as num).toInt(),
  to: json['to'] as String,
  commits: (json['commits'] as num).toInt(),
  groups: (json['groups'] as List<dynamic>)
      .map((e) => ReleaseNoteGroup.fromJson(e as Map<String, dynamic>))
      .toList(),
  slack: json['slack'] as String,
  whatsapp: json['whatsapp'] as String,
  from: json['from'] as String?,
  compareUrl: json['compareUrl'] as String?,
);

Map<String, dynamic> _$ReleaseNotesToJson(ReleaseNotes instance) =>
    <String, dynamic>{
      'releaseId': instance.releaseId,
      'version': instance.version,
      'build': instance.build,
      'from': ?instance.from,
      'to': instance.to,
      'commits': instance.commits,
      'groups': instance.groups.map((e) => e.toJson()).toList(),
      'compareUrl': ?instance.compareUrl,
      'slack': instance.slack,
      'whatsapp': instance.whatsapp,
    };

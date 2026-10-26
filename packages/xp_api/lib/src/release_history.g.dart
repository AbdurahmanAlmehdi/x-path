// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'release_history.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ReleaseEvent _$ReleaseEventFromJson(Map<String, dynamic> json) => ReleaseEvent(
  kind: $enumDecode(_$ReleaseEventKindEnumMap, json['kind']),
  at: DateTime.parse(json['at'] as String),
  store: $enumDecodeNullable(_$ReleaseStoreEnumMap, json['store']),
  detail: json['detail'] as String?,
  by: json['by'] as String?,
  runId: json['runId'] as String?,
  patchNumber: (json['patchNumber'] as num?)?.toInt(),
);

Map<String, dynamic> _$ReleaseEventToJson(ReleaseEvent instance) =>
    <String, dynamic>{
      'kind': _$ReleaseEventKindEnumMap[instance.kind]!,
      'at': instance.at.toIso8601String(),
      'store': ?_$ReleaseStoreEnumMap[instance.store],
      'detail': ?instance.detail,
      'by': ?instance.by,
      'runId': ?instance.runId,
      'patchNumber': ?instance.patchNumber,
    };

const _$ReleaseEventKindEnumMap = {
  ReleaseEventKind.created: 'created',
  ReleaseEventKind.build: 'build',
  ReleaseEventKind.store: 'store',
  ReleaseEventKind.mergeRequested: 'merge_requested',
  ReleaseEventKind.merged: 'merged',
  ReleaseEventKind.abandoned: 'abandoned',
  ReleaseEventKind.rolloutRequested: 'rollout_requested',
  ReleaseEventKind.rollout: 'rollout',
  ReleaseEventKind.patch: 'patch',
  ReleaseEventKind.patchRequested: 'patch_requested',
  ReleaseEventKind.patchPromoted: 'patch_promoted',
  ReleaseEventKind.patchRolledBack: 'patch_rolled_back',
  ReleaseEventKind.texts: 'texts',
};

const _$ReleaseStoreEnumMap = {
  ReleaseStore.apple: 'apple',
  ReleaseStore.play: 'play',
};

ReleaseHistory _$ReleaseHistoryFromJson(Map<String, dynamic> json) =>
    ReleaseHistory(
      (json['events'] as List<dynamic>)
          .map((e) => ReleaseEvent.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$ReleaseHistoryToJson(ReleaseHistory instance) =>
    <String, dynamic>{
      'events': instance.events.map((e) => e.toJson()).toList(),
    };

ReleaseTexts _$ReleaseTextsFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ReleaseTexts', json, ($checkedConvert) {
      final val = ReleaseTexts(
        whatsNew: $checkedConvert('whatsNew', (v) => v as String?),
        whatToTest: $checkedConvert('whatToTest', (v) => v as String?),
      );
      return val;
    });

Map<String, dynamic> _$ReleaseTextsToJson(ReleaseTexts instance) =>
    <String, dynamic>{
      'whatsNew': ?instance.whatsNew,
      'whatToTest': ?instance.whatToTest,
    };

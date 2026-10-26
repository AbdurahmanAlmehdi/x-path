// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'release.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

StoreStatus _$StoreStatusFromJson(Map<String, dynamic> json) => StoreStatus(
  store: $enumDecode(_$ReleaseStoreEnumMap, json['store']),
  state: $enumDecode(_$StoreStateEnumMap, json['state']),
  source: $enumDecode(_$StatusSourceEnumMap, json['source']),
  detail: json['detail'] as String?,
  checkedAt: json['checkedAt'] == null
      ? null
      : DateTime.parse(json['checkedAt'] as String),
  changedAt: json['changedAt'] == null
      ? null
      : DateTime.parse(json['changedAt'] as String),
  note: json['note'] as String?,
);

Map<String, dynamic> _$StoreStatusToJson(StoreStatus instance) =>
    <String, dynamic>{
      'store': _$ReleaseStoreEnumMap[instance.store]!,
      'state': _$StoreStateEnumMap[instance.state]!,
      'source': _$StatusSourceEnumMap[instance.source]!,
      'detail': ?instance.detail,
      'checkedAt': ?instance.checkedAt?.toIso8601String(),
      'changedAt': ?instance.changedAt?.toIso8601String(),
      'note': ?instance.note,
    };

const _$ReleaseStoreEnumMap = {
  ReleaseStore.apple: 'apple',
  ReleaseStore.play: 'play',
};

const _$StoreStateEnumMap = {
  StoreState.pending: 'pending',
  StoreState.uploaded: 'uploaded',
  StoreState.inReview: 'in_review',
  StoreState.rejected: 'rejected',
  StoreState.approved: 'approved',
  StoreState.live: 'live',
};

const _$StatusSourceEnumMap = {
  StatusSource.upload: 'upload',
  StatusSource.api: 'api',
  StatusSource.lookup: 'lookup',
  StatusSource.manual: 'manual',
};

ReleaseBuild _$ReleaseBuildFromJson(Map<String, dynamic> json) => ReleaseBuild(
  build: (json['build'] as num).toInt(),
  runId: json['runId'] as String,
  createdAt: DateTime.parse(json['createdAt'] as String),
);

Map<String, dynamic> _$ReleaseBuildToJson(ReleaseBuild instance) =>
    <String, dynamic>{
      'build': instance.build,
      'runId': instance.runId,
      'createdAt': instance.createdAt.toIso8601String(),
    };

Release _$ReleaseFromJson(Map<String, dynamic> json) => Release(
  id: json['id'] as String,
  projectId: json['projectId'] as String,
  app: json['app'] as String,
  flavor: json['flavor'] as String,
  version: json['version'] as String,
  build: (json['build'] as num).toInt(),
  state: $enumDecode(_$ReleaseStateEnumMap, json['state']),
  stores: (json['stores'] as List<dynamic>)
      .map((e) => StoreStatus.fromJson(e as Map<String, dynamic>))
      .toList(),
  builds: (json['builds'] as List<dynamic>)
      .map((e) => ReleaseBuild.fromJson(e as Map<String, dynamic>))
      .toList(),
  mergeEnabled: json['mergeEnabled'] as bool,
  createdAt: DateTime.parse(json['createdAt'] as String),
  updatedAt: DateTime.parse(json['updatedAt'] as String),
  branch: json['branch'] as String?,
  baseBranch: json['baseBranch'] as String?,
  tag: json['tag'] as String?,
  headSha: json['headSha'] as String?,
  prNumber: (json['prNumber'] as num?)?.toInt(),
  prUrl: json['prUrl'] as String?,
  mergeCommit: json['mergeCommit'] as String?,
  mergeRunId: json['mergeRunId'] as String?,
  message: json['message'] as String?,
  whatsNew: json['whatsNew'] as String?,
  whatToTest: json['whatToTest'] as String?,
);

Map<String, dynamic> _$ReleaseToJson(Release instance) => <String, dynamic>{
  'id': instance.id,
  'projectId': instance.projectId,
  'app': instance.app,
  'flavor': instance.flavor,
  'version': instance.version,
  'build': instance.build,
  'state': _$ReleaseStateEnumMap[instance.state]!,
  'stores': instance.stores.map((e) => e.toJson()).toList(),
  'builds': instance.builds.map((e) => e.toJson()).toList(),
  'mergeEnabled': instance.mergeEnabled,
  'branch': ?instance.branch,
  'baseBranch': ?instance.baseBranch,
  'tag': ?instance.tag,
  'headSha': ?instance.headSha,
  'prNumber': ?instance.prNumber,
  'prUrl': ?instance.prUrl,
  'mergeCommit': ?instance.mergeCommit,
  'mergeRunId': ?instance.mergeRunId,
  'message': ?instance.message,
  'whatsNew': ?instance.whatsNew,
  'whatToTest': ?instance.whatToTest,
  'createdAt': instance.createdAt.toIso8601String(),
  'updatedAt': instance.updatedAt.toIso8601String(),
};

const _$ReleaseStateEnumMap = {
  ReleaseState.draft: 'draft',
  ReleaseState.building: 'building',
  ReleaseState.uploaded: 'uploaded',
  ReleaseState.inReview: 'in_review',
  ReleaseState.rejected: 'rejected',
  ReleaseState.approved: 'approved',
  ReleaseState.live: 'live',
  ReleaseState.merged: 'merged',
  ReleaseState.abandoned: 'abandoned',
};

ReleasesResponse _$ReleasesResponseFromJson(Map<String, dynamic> json) =>
    ReleasesResponse(
      (json['releases'] as List<dynamic>)
          .map((e) => Release.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$ReleasesResponseToJson(ReleasesResponse instance) =>
    <String, dynamic>{
      'releases': instance.releases.map((e) => e.toJson()).toList(),
    };

StoreStatusRequest _$StoreStatusRequestFromJson(Map<String, dynamic> json) =>
    $checkedCreate('StoreStatusRequest', json, ($checkedConvert) {
      final val = StoreStatusRequest(
        state: $checkedConvert(
          'state',
          (v) => $enumDecode(_$StoreStateEnumMap, v),
        ),
      );
      return val;
    });

Map<String, dynamic> _$StoreStatusRequestToJson(StoreStatusRequest instance) =>
    <String, dynamic>{'state': _$StoreStateEnumMap[instance.state]!};

AbandonRequest _$AbandonRequestFromJson(Map<String, dynamic> json) =>
    $checkedCreate('AbandonRequest', json, ($checkedConvert) {
      final val = AbandonRequest(
        reason: $checkedConvert('reason', (v) => v as String?),
      );
      return val;
    });

Map<String, dynamic> _$AbandonRequestToJson(AbandonRequest instance) =>
    <String, dynamic>{'reason': ?instance.reason};

RolloutRequest _$RolloutRequestFromJson(Map<String, dynamic> json) =>
    RolloutRequest(
      store: $enumDecode(_$ReleaseStoreEnumMap, json['store']),
      action: $enumDecode(_$RolloutActionEnumMap, json['action']),
      userFraction: (json['userFraction'] as num?)?.toDouble(),
    );

Map<String, dynamic> _$RolloutRequestToJson(RolloutRequest instance) =>
    <String, dynamic>{
      'store': _$ReleaseStoreEnumMap[instance.store]!,
      'action': _$RolloutActionEnumMap[instance.action]!,
      'userFraction': ?instance.userFraction,
    };

const _$RolloutActionEnumMap = {
  RolloutAction.pause: 'pause',
  RolloutAction.resume: 'resume',
  RolloutAction.complete: 'complete',
  RolloutAction.halt: 'halt',
  RolloutAction.fraction: 'fraction',
};

// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'run.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DispatchRequest _$DispatchRequestFromJson(Map<String, dynamic> json) =>
    $checkedCreate('DispatchRequest', json, ($checkedConvert) {
      final val = DispatchRequest(
        ref: $checkedConvert('ref', (v) => v as String?),
        app: $checkedConvert('app', (v) => v as String?),
        flavors: $checkedConvert(
          'flavors',
          (v) => (v as List<dynamic>?)?.map((e) => e as String).toList(),
        ),
        platforms: $checkedConvert(
          'platforms',
          (v) => (v as List<dynamic>?)?.map((e) => e as String).toList(),
        ),
        bump: $checkedConvert(
          'bump',
          (v) => $enumDecodeNullable(_$VersionBumpEnumMap, v),
        ),
        version: $checkedConvert('version', (v) => v as String?),
        releaseVersion: $checkedConvert('releaseVersion', (v) => v as String?),
        release: $checkedConvert('release', (v) => v as String?),
        inputs: $checkedConvert(
          'inputs',
          (v) => v as Map<String, dynamic>? ?? const {},
        ),
      );
      return val;
    });

Map<String, dynamic> _$DispatchRequestToJson(DispatchRequest instance) =>
    <String, dynamic>{
      'ref': ?instance.ref,
      'app': ?instance.app,
      'flavors': ?instance.flavors,
      'platforms': ?instance.platforms,
      'bump': ?_$VersionBumpEnumMap[instance.bump],
      'version': ?instance.version,
      'releaseVersion': ?instance.releaseVersion,
      'release': ?instance.release,
      'inputs': instance.inputs,
    };

const _$VersionBumpEnumMap = {
  VersionBump.major: 'major',
  VersionBump.minor: 'minor',
  VersionBump.patch: 'patch',
  VersionBump.keep: 'keep',
};

RunJob _$RunJobFromJson(Map<String, dynamic> json) => RunJob(
  id: json['id'] as String,
  name: json['name'] as String,
  stage: (json['stage'] as num).toInt(),
  state: $enumDecode(_$JobStateEnumMap, json['state']),
  capabilities:
      (json['capabilities'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const [],
  message: json['message'] as String?,
);

Map<String, dynamic> _$RunJobToJson(RunJob instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'stage': instance.stage,
  'state': _$JobStateEnumMap[instance.state]!,
  'capabilities': instance.capabilities,
  'message': ?instance.message,
};

const _$JobStateEnumMap = {
  JobState.queued: 'queued',
  JobState.running: 'running',
  JobState.succeeded: 'succeeded',
  JobState.failed: 'failed',
  JobState.cancelled: 'cancelled',
  JobState.interrupted: 'interrupted',
  JobState.waitingForResume: 'waiting_for_resume',
  JobState.waitingForApproval: 'waiting_for_approval',
};

Run _$RunFromJson(Map<String, dynamic> json) => Run(
  id: json['id'] as String,
  projectId: json['projectId'] as String,
  workflowId: json['workflowId'] as String,
  workflowVersionId: json['workflowVersionId'] as String,
  sha: json['sha'] as String,
  state: $enumDecode(_$RunStateEnumMap, json['state']),
  locksProject: json['locksProject'] as bool,
  createdAt: DateTime.parse(json['createdAt'] as String),
  jobs: (json['jobs'] as List<dynamic>)
      .map((e) => RunJob.fromJson(e as Map<String, dynamic>))
      .toList(),
  ref: json['ref'] as String?,
  version: json['version'] as String?,
  build: (json['build'] as num?)?.toInt(),
  request: json['request'] == null
      ? null
      : DispatchRequest.fromJson(json['request'] as Map<String, dynamic>),
);

Map<String, dynamic> _$RunToJson(Run instance) => <String, dynamic>{
  'id': instance.id,
  'projectId': instance.projectId,
  'workflowId': instance.workflowId,
  'workflowVersionId': instance.workflowVersionId,
  'sha': instance.sha,
  'ref': ?instance.ref,
  'state': _$RunStateEnumMap[instance.state]!,
  'locksProject': instance.locksProject,
  'version': ?instance.version,
  'build': ?instance.build,
  'createdAt': instance.createdAt.toIso8601String(),
  'jobs': instance.jobs.map((e) => e.toJson()).toList(),
  'request': ?instance.request?.toJson(),
};

const _$RunStateEnumMap = {
  RunState.queued: 'queued',
  RunState.running: 'running',
  RunState.waitingForApproval: 'waiting_for_approval',
  RunState.succeeded: 'succeeded',
  RunState.failed: 'failed',
  RunState.cancelled: 'cancelled',
};

RunsResponse _$RunsResponseFromJson(Map<String, dynamic> json) => RunsResponse(
  (json['runs'] as List<dynamic>)
      .map((e) => Run.fromJson(e as Map<String, dynamic>))
      .toList(),
  next: json['next'] as String?,
);

Map<String, dynamic> _$RunsResponseToJson(RunsResponse instance) =>
    <String, dynamic>{
      'runs': instance.runs.map((e) => e.toJson()).toList(),
      'next': ?instance.next,
    };

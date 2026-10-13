// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'job.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

JobStep _$JobStepFromJson(Map<String, dynamic> json) => JobStep(
  ordinal: (json['ordinal'] as num).toInt(),
  kind: json['kind'] as String,
  state: $enumDecode(_$StepStateEnumMap, json['state']),
  sideEffect: json['sideEffect'] as bool,
  attempts: (json['attempts'] as num).toInt(),
  result: json['result'] as Map<String, dynamic>?,
  message: json['message'] as String?,
  startedAt: json['startedAt'] == null
      ? null
      : DateTime.parse(json['startedAt'] as String),
  finishedAt: json['finishedAt'] == null
      ? null
      : DateTime.parse(json['finishedAt'] as String),
);

Map<String, dynamic> _$JobStepToJson(JobStep instance) => <String, dynamic>{
  'ordinal': instance.ordinal,
  'kind': instance.kind,
  'state': _$StepStateEnumMap[instance.state]!,
  'sideEffect': instance.sideEffect,
  'attempts': instance.attempts,
  'result': ?instance.result,
  'message': ?instance.message,
  'startedAt': ?instance.startedAt?.toIso8601String(),
  'finishedAt': ?instance.finishedAt?.toIso8601String(),
};

const _$StepStateEnumMap = {
  StepState.pending: 'pending',
  StepState.running: 'running',
  StepState.succeeded: 'succeeded',
  StepState.failed: 'failed',
  StepState.skipped: 'skipped',
  StepState.cancelled: 'cancelled',
  StepState.interrupted: 'interrupted',
};

Job _$JobFromJson(Map<String, dynamic> json) => Job(
  id: json['id'] as String,
  projectId: json['projectId'] as String,
  workflowVersionId: json['workflowVersionId'] as String,
  state: $enumDecode(_$JobStateEnumMap, json['state']),
  createdAt: DateTime.parse(json['createdAt'] as String),
  steps: (json['steps'] as List<dynamic>)
      .map((e) => JobStep.fromJson(e as Map<String, dynamic>))
      .toList(),
  releaseId: json['releaseId'] as String?,
  sha: json['sha'] as String?,
  runnerId: json['runnerId'] as String?,
  message: json['message'] as String?,
  startedAt: json['startedAt'] == null
      ? null
      : DateTime.parse(json['startedAt'] as String),
  finishedAt: json['finishedAt'] == null
      ? null
      : DateTime.parse(json['finishedAt'] as String),
);

Map<String, dynamic> _$JobToJson(Job instance) => <String, dynamic>{
  'id': instance.id,
  'projectId': instance.projectId,
  'workflowVersionId': instance.workflowVersionId,
  'releaseId': ?instance.releaseId,
  'sha': ?instance.sha,
  'state': _$JobStateEnumMap[instance.state]!,
  'runnerId': ?instance.runnerId,
  'message': ?instance.message,
  'createdAt': instance.createdAt.toIso8601String(),
  'startedAt': ?instance.startedAt?.toIso8601String(),
  'finishedAt': ?instance.finishedAt?.toIso8601String(),
  'steps': instance.steps.map((e) => e.toJson()).toList(),
};

const _$JobStateEnumMap = {
  JobState.queued: 'queued',
  JobState.running: 'running',
  JobState.succeeded: 'succeeded',
  JobState.failed: 'failed',
  JobState.cancelled: 'cancelled',
  JobState.interrupted: 'interrupted',
  JobState.waitingForResume: 'waiting_for_resume',
};

ResumeJobRequest _$ResumeJobRequestFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ResumeJobRequest', json, ($checkedConvert) {
      final val = ResumeJobRequest(
        fromStep: $checkedConvert('fromStep', (v) => (v as num?)?.toInt()),
      );
      return val;
    });

Map<String, dynamic> _$ResumeJobRequestToJson(ResumeJobRequest instance) =>
    <String, dynamic>{'fromStep': ?instance.fromStep};

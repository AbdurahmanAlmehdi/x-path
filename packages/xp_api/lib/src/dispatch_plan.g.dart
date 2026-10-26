// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dispatch_plan.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DispatchPlan _$DispatchPlanFromJson(Map<String, dynamic> json) => DispatchPlan(
  flavors: (json['flavors'] as List<dynamic>).map((e) => e as String).toList(),
  platforms: (json['platforms'] as List<dynamic>)
      .map((e) => e as String)
      .toList(),
  stages:
      (json['stages'] as List<dynamic>?)
          ?.map((e) => PlannedStage.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
  skipped:
      (json['skipped'] as List<dynamic>?)
          ?.map((e) => SkippedJob.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
  currentVersion: json['currentVersion'] as String?,
  version: json['version'] as String?,
  build: (json['build'] as num?)?.toInt(),
  releaseVersion: json['releaseVersion'] as String?,
);

Map<String, dynamic> _$DispatchPlanToJson(DispatchPlan instance) =>
    <String, dynamic>{
      'flavors': instance.flavors,
      'platforms': instance.platforms,
      'stages': instance.stages.map((e) => e.toJson()).toList(),
      'skipped': instance.skipped.map((e) => e.toJson()).toList(),
      'currentVersion': ?instance.currentVersion,
      'version': ?instance.version,
      'build': ?instance.build,
      'releaseVersion': ?instance.releaseVersion,
    };

PlannedStage _$PlannedStageFromJson(Map<String, dynamic> json) => PlannedStage(
  name: json['name'] as String,
  jobs:
      (json['jobs'] as List<dynamic>?)
          ?.map((e) => PlannedJob.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
  gates:
      (json['gates'] as List<dynamic>?)?.map((e) => e as String).toList() ??
      const [],
);

Map<String, dynamic> _$PlannedStageToJson(PlannedStage instance) =>
    <String, dynamic>{
      'name': instance.name,
      'jobs': instance.jobs.map((e) => e.toJson()).toList(),
      'gates': instance.gates,
    };

PlannedJob _$PlannedJobFromJson(Map<String, dynamic> json) => PlannedJob(
  name: json['name'] as String,
  engineOnly: json['engineOnly'] as bool,
  local: json['local'] as bool,
  capabilities:
      (json['capabilities'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const [],
  flavor: json['flavor'] as String?,
  platform: json['platform'] as String?,
  runner: json['runner'] as String?,
  waitReason: json['waitReason'] as String?,
  narrowing:
      (json['narrowing'] as List<dynamic>?)?.map((e) => e as String).toList() ??
      const [],
);

Map<String, dynamic> _$PlannedJobToJson(PlannedJob instance) =>
    <String, dynamic>{
      'name': instance.name,
      'flavor': ?instance.flavor,
      'platform': ?instance.platform,
      'capabilities': instance.capabilities,
      'engineOnly': instance.engineOnly,
      'local': instance.local,
      'runner': ?instance.runner,
      'waitReason': ?instance.waitReason,
      'narrowing': instance.narrowing,
    };

SkippedJob _$SkippedJobFromJson(Map<String, dynamic> json) => SkippedJob(
  name: json['name'] as String,
  stage: json['stage'] as String,
  reason: json['reason'] as String,
  flavor: json['flavor'] as String?,
  platform: json['platform'] as String?,
  blocks: json['blocks'] as bool? ?? false,
);

Map<String, dynamic> _$SkippedJobToJson(SkippedJob instance) =>
    <String, dynamic>{
      'name': instance.name,
      'stage': instance.stage,
      'flavor': ?instance.flavor,
      'platform': ?instance.platform,
      'reason': instance.reason,
      'blocks': instance.blocks,
    };

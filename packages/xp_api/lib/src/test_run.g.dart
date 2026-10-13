// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'test_run.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TestRef _$TestRefFromJson(Map<String, dynamic> json) =>
    TestRef(suite: json['suite'] as String, name: json['name'] as String);

Map<String, dynamic> _$TestRefToJson(TestRef instance) => <String, dynamic>{
  'suite': instance.suite,
  'name': instance.name,
};

TestCase _$TestCaseFromJson(Map<String, dynamic> json) => TestCase(
  suite: json['suite'] as String,
  name: json['name'] as String,
  status: $enumDecode(_$TestStatusEnumMap, json['status']),
  message: json['message'] as String?,
  stackTrace: json['stackTrace'] as String?,
);

Map<String, dynamic> _$TestCaseToJson(TestCase instance) => <String, dynamic>{
  'suite': instance.suite,
  'name': instance.name,
  'status': _$TestStatusEnumMap[instance.status]!,
  'message': ?instance.message,
  'stackTrace': ?instance.stackTrace,
};

const _$TestStatusEnumMap = {
  TestStatus.passed: 'passed',
  TestStatus.failed: 'failed',
  TestStatus.errored: 'errored',
  TestStatus.skipped: 'skipped',
};

TestCounts _$TestCountsFromJson(Map<String, dynamic> json) => TestCounts(
  total: (json['total'] as num).toInt(),
  passed: (json['passed'] as num).toInt(),
  failed: (json['failed'] as num).toInt(),
  errored: (json['errored'] as num).toInt(),
  skipped: (json['skipped'] as num).toInt(),
);

Map<String, dynamic> _$TestCountsToJson(TestCounts instance) =>
    <String, dynamic>{
      'total': instance.total,
      'passed': instance.passed,
      'failed': instance.failed,
      'errored': instance.errored,
      'skipped': instance.skipped,
    };

TestRunDiff _$TestRunDiffFromJson(Map<String, dynamic> json) => TestRunDiff(
  newFailures: (json['newFailures'] as List<dynamic>)
      .map((e) => TestRef.fromJson(e as Map<String, dynamic>))
      .toList(),
  fixed: (json['fixed'] as List<dynamic>)
      .map((e) => TestRef.fromJson(e as Map<String, dynamic>))
      .toList(),
  missing: (json['missing'] as List<dynamic>)
      .map((e) => TestRef.fromJson(e as Map<String, dynamic>))
      .toList(),
  stillFailing: (json['stillFailing'] as num).toInt(),
  comparedTo: json['comparedTo'] as String?,
);

Map<String, dynamic> _$TestRunDiffToJson(TestRunDiff instance) =>
    <String, dynamic>{
      'comparedTo': ?instance.comparedTo,
      'newFailures': instance.newFailures.map((e) => e.toJson()).toList(),
      'fixed': instance.fixed.map((e) => e.toJson()).toList(),
      'missing': instance.missing.map((e) => e.toJson()).toList(),
      'stillFailing': instance.stillFailing,
    };

TestRun _$TestRunFromJson(Map<String, dynamic> json) => TestRun(
  id: json['id'] as String,
  jobId: json['jobId'] as String,
  branch: json['branch'] as String,
  appPath: json['appPath'] as String,
  baseline: json['baseline'] as bool,
  createdAt: DateTime.parse(json['createdAt'] as String),
  counts: TestCounts.fromJson(json['counts'] as Map<String, dynamic>),
  diff: TestRunDiff.fromJson(json['diff'] as Map<String, dynamic>),
);

Map<String, dynamic> _$TestRunToJson(TestRun instance) => <String, dynamic>{
  'id': instance.id,
  'jobId': instance.jobId,
  'branch': instance.branch,
  'appPath': instance.appPath,
  'baseline': instance.baseline,
  'createdAt': instance.createdAt.toIso8601String(),
  'counts': instance.counts.toJson(),
  'diff': instance.diff.toJson(),
};

TestRunResponse _$TestRunResponseFromJson(Map<String, dynamic> json) =>
    TestRunResponse(
      run: TestRun.fromJson(json['run'] as Map<String, dynamic>),
      total: (json['total'] as num).toInt(),
      offset: (json['offset'] as num).toInt(),
      tests: (json['tests'] as List<dynamic>)
          .map((e) => TestCase.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$TestRunResponseToJson(TestRunResponse instance) =>
    <String, dynamic>{
      'run': instance.run.toJson(),
      'total': instance.total,
      'offset': instance.offset,
      'tests': instance.tests.map((e) => e.toJson()).toList(),
    };

TestBaseline _$TestBaselineFromJson(Map<String, dynamic> json) => TestBaseline(
  appPath: json['appPath'] as String,
  branch: json['branch'] as String,
  jobId: json['jobId'] as String,
  createdAt: DateTime.parse(json['createdAt'] as String),
  counts: TestCounts.fromJson(json['counts'] as Map<String, dynamic>),
);

Map<String, dynamic> _$TestBaselineToJson(TestBaseline instance) =>
    <String, dynamic>{
      'appPath': instance.appPath,
      'branch': instance.branch,
      'jobId': instance.jobId,
      'createdAt': instance.createdAt.toIso8601String(),
      'counts': instance.counts.toJson(),
    };

TestBaselinesResponse _$TestBaselinesResponseFromJson(
  Map<String, dynamic> json,
) => TestBaselinesResponse(
  (json['baselines'] as List<dynamic>)
      .map((e) => TestBaseline.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$TestBaselinesResponseToJson(
  TestBaselinesResponse instance,
) => <String, dynamic>{
  'baselines': instance.baselines.map((e) => e.toJson()).toList(),
};

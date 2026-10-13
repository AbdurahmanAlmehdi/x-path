// `json_serializable` cannot parse `factory .name` constructors yet.
// ignore_for_file: unnecessary_type_name_in_constructor

import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'test_run.g.dart';

/// How a test ended (D-21).
@JsonEnum(valueField: 'wire')
enum TestStatus {
  /// It ran and passed.
  passed('passed'),

  /// An expectation failed.
  failed('failed'),

  /// It threw, or its file could not be loaded.
  errored('errored'),

  /// It did not run.
  skipped('skipped');

  new(this.wire);

  /// The name on the wire.
  final String wire;

  /// Whether the test counts as a failure: [failed] or [errored].
  bool get isFailure => this == failed || this == errored;
}

/// The stable identity of a test: the test file relative to the app, and the
/// full test name with the names of its groups.
@JsonSerializable()
class TestRef extends Equatable {
  /// Creates a reference.
  const new({required this.suite, required this.name});

  /// Reads a reference from its JSON form.
  factory TestRef.fromJson(Map<String, dynamic> json) =>
      _$TestRefFromJson(json);

  /// The test file relative to the app, such as `test/math_test.dart`.
  final String suite;

  /// The full name, such as `arithmetic division rounds down`.
  final String name;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$TestRefToJson(this);

  @override
  List<Object?> get props => [suite, name];
}

/// One test of a run and how it ended.
@JsonSerializable(includeIfNull: false)
class TestCase extends Equatable {
  /// Creates a test case.
  const new({
    required this.suite,
    required this.name,
    required this.status,
    this.message,
    this.stackTrace,
  });

  /// Reads a test case from its JSON form.
  factory TestCase.fromJson(Map<String, dynamic> json) =>
      _$TestCaseFromJson(json);

  /// The test file relative to the app.
  final String suite;

  /// The full name with the names of its groups.
  final String name;

  /// How it ended.
  final TestStatus status;

  /// What went wrong, for a failure.
  final String? message;

  /// Where, for a failure.
  final String? stackTrace;

  /// The identity of the test.
  TestRef get ref => TestRef(suite: suite, name: name);

  /// The JSON form.
  Map<String, dynamic> toJson() => _$TestCaseToJson(this);

  @override
  List<Object?> get props => [suite, name, status, message, stackTrace];
}

/// How many tests of a run ended each way.
@JsonSerializable()
class TestCounts extends Equatable {
  /// Creates the counts.
  const new({
    required this.total,
    required this.passed,
    required this.failed,
    required this.errored,
    required this.skipped,
  });

  /// Reads the counts from their JSON form.
  factory TestCounts.fromJson(Map<String, dynamic> json) =>
      _$TestCountsFromJson(json);

  /// Every test of the run.
  final int total;

  /// Tests that passed.
  final int passed;

  /// Tests with a failed expectation.
  final int failed;

  /// Tests that threw.
  final int errored;

  /// Tests that did not run.
  final int skipped;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$TestCountsToJson(this);

  @override
  List<Object?> get props => [total, passed, failed, errored, skipped];
}

/// What a run changed against the baseline.
@JsonSerializable(explicitToJson: true, includeIfNull: false)
class TestRunDiff extends Equatable {
  /// Creates a diff.
  const new({
    required this.newFailures,
    required this.fixed,
    required this.missing,
    required this.stillFailing,
    this.comparedTo,
  });

  /// Reads a diff from its JSON form.
  factory TestRunDiff.fromJson(Map<String, dynamic> json) =>
      _$TestRunDiffFromJson(json);

  /// The job of the baseline run this was compared with, or `null` if there
  /// was no baseline: then every failure is new.
  final String? comparedTo;

  /// Tests that fail now and did not fail in the baseline, or are not in it.
  final List<TestRef> newFailures;

  /// Tests that failed in the baseline and pass now.
  final List<TestRef> fixed;

  /// Tests of the baseline that this run did not report.
  final List<TestRef> missing;

  /// How many tests fail now as they did in the baseline.
  final int stillFailing;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$TestRunDiffToJson(this);

  @override
  List<Object?> get props => [
    comparedTo,
    newFailures,
    fixed,
    missing,
    stillFailing,
  ];
}

/// A `flutter test` run of a job.
@JsonSerializable(explicitToJson: true)
class TestRun extends Equatable {
  /// Creates a run.
  const new({
    required this.id,
    required this.jobId,
    required this.branch,
    required this.appPath,
    required this.baseline,
    required this.createdAt,
    required this.counts,
    required this.diff,
  });

  /// Reads a run from its JSON form.
  factory TestRun.fromJson(Map<String, dynamic> json) =>
      _$TestRunFromJson(json);

  /// The engine's id, for example `tst_1a2b3c4d5e6f7a8b`.
  final String id;

  /// The job that ran the tests.
  final String jobId;

  /// The branch that was tested.
  final String branch;

  /// The app that was tested, relative to the repository (`.` for the root).
  final String appPath;

  /// Whether this run is a baseline: a run of the base branch that later runs
  /// are compared with.
  final bool baseline;

  /// When the run ended, in UTC.
  final DateTime createdAt;

  /// How the tests ended.
  final TestCounts counts;

  /// What changed against the baseline.
  final TestRunDiff diff;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$TestRunToJson(this);

  @override
  List<Object?> get props => [
    id,
    jobId,
    branch,
    appPath,
    baseline,
    createdAt,
    counts,
    diff,
  ];
}

/// The body of `GET /jobs/{id}/tests`: the run and a page of its tests.
@JsonSerializable(explicitToJson: true)
class TestRunResponse extends Equatable {
  /// Creates the response.
  const new({
    required this.run,
    required this.total,
    required this.offset,
    required this.tests,
  });

  /// Reads the response from its JSON form.
  factory TestRunResponse.fromJson(Map<String, dynamic> json) =>
      _$TestRunResponseFromJson(json);

  /// The run.
  final TestRun run;

  /// How many tests match the request, over all pages.
  final int total;

  /// Where this page starts among the matching tests.
  final int offset;

  /// The page, ordered by file and name.
  final List<TestCase> tests;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$TestRunResponseToJson(this);

  @override
  List<Object?> get props => [run, total, offset, tests];
}

/// The run that later runs of an app are compared with, on one branch.
@JsonSerializable(explicitToJson: true)
class TestBaseline extends Equatable {
  /// Creates a baseline.
  const new({
    required this.appPath,
    required this.branch,
    required this.jobId,
    required this.createdAt,
    required this.counts,
  });

  /// Reads a baseline from its JSON form.
  factory TestBaseline.fromJson(Map<String, dynamic> json) =>
      _$TestBaselineFromJson(json);

  /// The app, relative to the repository (`.` for the root).
  final String appPath;

  /// The base branch.
  final String branch;

  /// The job whose run is the baseline.
  final String jobId;

  /// When that run ended, in UTC.
  final DateTime createdAt;

  /// How its tests ended.
  final TestCounts counts;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$TestBaselineToJson(this);

  @override
  List<Object?> get props => [appPath, branch, jobId, createdAt, counts];
}

/// The body of `GET /projects/{id}/tests/baseline`.
@JsonSerializable(explicitToJson: true)
class TestBaselinesResponse extends Equatable {
  /// Creates the response.
  const new(this.baselines);

  /// Reads the response from its JSON form.
  factory TestBaselinesResponse.fromJson(Map<String, dynamic> json) =>
      _$TestBaselinesResponseFromJson(json);

  /// The current baseline of every app and branch of the project.
  final List<TestBaseline> baselines;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$TestBaselinesResponseToJson(this);

  @override
  List<Object?> get props => [baselines];
}

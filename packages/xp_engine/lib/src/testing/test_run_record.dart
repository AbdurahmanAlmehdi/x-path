import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/json_fields.dart';
import 'package:xp_engine/src/testing/test_run_results.dart';

/// What the engine stores about the test run of a job (`test_run`).
class TestRunRecord extends Equatable {
  /// Creates a record.
  const new({
    required this.id,
    required this.jobId,
    required this.projectId,
    required this.branch,
    required this.appPath,
    required this.baseline,
    required this.createdAt,
    required this.results,
    required this.diff,
  });

  /// Reads the record back from the stored columns and the `results` JSON
  /// [resultsJson] wrote.
  ///
  /// Throws a [FormatException] if [stored] is not valid.
  factory fromStored({
    required String id,
    required String jobId,
    required String projectId,
    required String branch,
    required String appPath,
    required bool baseline,
    required DateTime createdAt,
    required Map<String, dynamic> stored,
  }) => TestRunRecord(
    id: id,
    jobId: jobId,
    projectId: projectId,
    branch: branch,
    appPath: appPath,
    baseline: baseline,
    createdAt: createdAt,
    results: TestRunResults.fromJson(stored),
    diff: TestRunDiff.fromJson(requiredObject(stored, 'diff')),
  );

  /// The engine's id, for example `tst_1a2b3c4d5e6f7a8b`.
  final String id;

  /// The job that ran the tests. A job has one run.
  final String jobId;

  /// The project of the job.
  final String projectId;

  /// The branch that was tested.
  final String branch;

  /// The app that was tested, relative to the repository (`.` for the root).
  final String appPath;

  /// Whether later runs of this app on this branch are compared with this
  /// run (until a newer baseline replaces it).
  final bool baseline;

  /// When the run ended.
  final DateTime createdAt;

  /// How every test ended.
  final TestRunResults results;

  /// What changed against the baseline the run was compared with.
  final TestRunDiff diff;

  /// The `results` column: the tests in their compact form and the diff.
  Map<String, dynamic> resultsJson() => {
    ...results.toJson(),
    'diff': diff.toJson(),
  };

  /// The record as the API shows it.
  TestRun toTestRun() => TestRun(
    id: id,
    jobId: jobId,
    branch: branch,
    appPath: appPath,
    baseline: baseline,
    createdAt: createdAt,
    counts: results.counts,
    diff: diff,
  );

  /// The record as a baseline, as the API shows it.
  TestBaseline toTestBaseline() => TestBaseline(
    appPath: appPath,
    branch: branch,
    jobId: jobId,
    createdAt: createdAt,
    counts: results.counts,
  );

  @override
  List<Object?> get props => [
    id,
    jobId,
    projectId,
    branch,
    appPath,
    baseline,
    createdAt,
    results,
    diff,
  ];
}

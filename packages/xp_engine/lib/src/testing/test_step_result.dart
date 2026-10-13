import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';

/// What the `test` step reports in the job: the numbers; the tests are in
/// the test run of the job.
class TestStepResult extends Equatable {
  /// Creates the result.
  const new({
    required this.runId,
    required this.counts,
    required this.newFailures,
    required this.fixed,
    required this.missing,
    required this.stillFailing,
    required this.baseline,
    required this.seeded,
    this.comparedTo,
  });

  /// The id of the stored test run.
  final String runId;

  /// How the tests ended.
  final TestCounts counts;

  /// How many tests fail that did not fail in the baseline. Not zero only if
  /// the run seeded the baseline.
  final int newFailures;

  /// How many tests failed in the baseline and pass now.
  final int fixed;

  /// How many tests of the baseline this run did not report.
  final int missing;

  /// How many tests fail as they did in the baseline.
  final int stillFailing;

  /// Whether this run is the baseline from now on.
  final bool baseline;

  /// Whether it is because there was no baseline before.
  final bool seeded;

  /// The job of the baseline it was compared with, if there was one.
  final String? comparedTo;

  /// The stored form.
  Map<String, dynamic> toJson() => {
    'runId': runId,
    'counts': counts.toJson(),
    'newFailures': newFailures,
    'fixed': fixed,
    'missing': missing,
    'stillFailing': stillFailing,
    'baseline': baseline,
    'seeded': seeded,
    'comparedTo': ?comparedTo,
  };

  @override
  List<Object?> get props => [
    runId,
    counts,
    newFailures,
    fixed,
    missing,
    stillFailing,
    baseline,
    seeded,
    comparedTo,
  ];
}

import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/testing/test_run_diff.dart';
import 'package:xp_engine/src/testing/test_run_record.dart';
import 'package:xp_engine/src/testing/test_run_results.dart';

/// What a finished run means for the job and for the baseline.
class TestEvaluation {
  /// Creates an evaluation.
  const new({
    required this.diff,
    required this.becomesBaseline,
    required this.seeded,
  });

  /// What changed against the baseline.
  final TestRunDiff diff;

  /// Whether the run is the baseline of its app and branch from now on.
  final bool becomesBaseline;

  /// Whether it became the baseline because there was none: the failures it
  /// has are accepted as they are.
  final bool seeded;

  /// Whether the `test` step fails: the run has failures that the baseline
  /// does not. A run that seeds the baseline never fails the step.
  bool get failsStep => diff.newFailures.isNotEmpty && !seeded;
}

/// Judges a run of the tests against [baseline] (D-21).
///
/// The baseline is the last green run on the base branch, where green means
/// no new failures against the baseline before it. Failures that a baseline
/// already has do not fail a step, so a project with failing tests it has not
/// fixed yet can still ship. The very first run on the base branch has no
/// baseline to be green against: it seeds the baseline whatever it reports.
///
/// Only a complete run counts as a baseline: [filtered] says that the run was
/// limited to some files or tags. [expected] says which tests of the baseline
/// the run should have reported again.
TestEvaluation evaluateTestRun({
  required TestRunResults results,
  required TestRunRecord? baseline,
  required bool onBaseBranch,
  required bool filtered,
  required ExpectedTests expected,
}) {
  final diff = diffTestRuns(
    results,
    baseline?.results,
    comparedTo: baseline?.jobId,
    expected: expected,
  );
  final complete = onBaseBranch && !filtered;
  final seeded = complete && baseline == null;
  return TestEvaluation(
    diff: diff,
    becomesBaseline: seeded || (complete && diff.newFailures.isEmpty),
    seeded: seeded,
  );
}

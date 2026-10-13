import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/testing/test_run_results.dart';

int _byIdentity(TestRef a, TestRef b) {
  final bySuite = a.suite.compareTo(b.suite);
  return bySuite != 0 ? bySuite : a.name.compareTo(b.name);
}

/// Which tests of the baseline a run is expected to report again.
enum ExpectedTests {
  /// All of them: the run covered everything, so a test that is gone, or a
  /// whole file that is gone, is missing.
  all,

  /// Those of the files the run reported tests of: a run of some files says
  /// nothing about the others.
  ranSuites,

  /// None: the run was cut down inside the files (by tags), so nothing can be
  /// called missing.
  none,
}

/// What [current] changed against [baseline] (D-21).
///
/// A new failure is a test that fails now and did not fail in the baseline,
/// or is not in it. A fixed test failed in the baseline and passes now. A
/// missing test is in the baseline but not in this run, where [expected] says
/// the run should have reported it.
///
/// Without a baseline every failure is new.
TestRunDiff diffTestRuns(
  TestRunResults current,
  TestRunResults? baseline, {
  String? comparedTo,
  ExpectedTests expected = ExpectedTests.all,
}) {
  final newFailures = <TestRef>[];
  var stillFailing = 0;
  for (final test in current.failures) {
    if (baseline?[test.ref]?.status.isFailure ?? false) {
      stillFailing++;
    } else {
      newFailures.add(test.ref);
    }
  }
  final fixed = <TestRef>[];
  final missing = <TestRef>[];
  if (baseline != null) {
    final suites = current.suites;
    for (final test in baseline.tests) {
      final now = current[test.ref];
      if (now == null) {
        final expectedHere = switch (expected) {
          ExpectedTests.all => true,
          ExpectedTests.ranSuites => suites.contains(test.suite),
          ExpectedTests.none => false,
        };
        if (expectedHere) missing.add(test.ref);
      } else if (test.status.isFailure && now.status == TestStatus.passed) {
        fixed.add(test.ref);
      }
    }
  }
  return TestRunDiff(
    comparedTo: comparedTo,
    newFailures: newFailures..sort(_byIdentity),
    fixed: fixed..sort(_byIdentity),
    missing: missing..sort(_byIdentity),
    stillFailing: stillFailing,
  );
}

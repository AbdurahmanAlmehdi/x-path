import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

/// A stored run of [tests] (name to status, all in `test/a_test.dart`).
TestRunRecord testRunRecord({
  String id = 'tst_1',
  String jobId = 'job_1',
  String projectId = 'prj_1',
  String branch = 'main',
  String appPath = '.',
  bool baseline = true,
  DateTime? createdAt,
  Map<String, TestStatus> tests = const {
    'ok': TestStatus.passed,
    'bad': TestStatus.failed,
  },
}) {
  final results = TestRunResults.of([
    for (final MapEntry(:key, :value) in tests.entries)
      TestCase(
        suite: 'test/a_test.dart',
        name: key,
        status: value,
        message: value.isFailure ? 'it failed' : null,
      ),
  ]);
  return TestRunRecord(
    id: id,
    jobId: jobId,
    projectId: projectId,
    branch: branch,
    appPath: appPath,
    baseline: baseline,
    createdAt: createdAt ?? DateTime.utc(2026, 10, 13),
    results: results,
    diff: diffTestRuns(results, null),
  );
}

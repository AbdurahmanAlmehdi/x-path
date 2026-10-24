import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

/// A project the test runs belong to: `prj_1`, the project of every job
/// `TestEngine.createJob` makes.
ProjectRecord testRunProject() => ProjectRecord(
  id: 'prj_1',
  host: 'github.com',
  sourceKey: '42',
  githubRepoId: 42,
  fullName: 'octo/app',
  remote: 'https://github.com/octo/app.git',
  githubDefaultBranch: 'main',
  scan: const ProjectProfile(),
  findings: const [],
  scannedAt: DateTime.utc(2026),
);

/// A run of the job [jobId]: two passing tests, two failures (`old failure`
/// is in [baseline], `new failure` is not) and a skipped one.
TestRunRecord sampleTestRun(
  String jobId, {
  String branch = 'main',
  String appPath = '.',
  bool baseline = false,
  DateTime? createdAt,
}) {
  final results = TestRunResults.of(const [
    TestCase(
      suite: 'test/a_test.dart',
      name: 'a ok',
      status: TestStatus.passed,
    ),
    TestCase(
      suite: 'test/a_test.dart',
      name: 'b ok',
      status: TestStatus.passed,
    ),
    TestCase(
      suite: 'test/a_test.dart',
      name: 'old failure',
      status: TestStatus.failed,
      message: 'Expected: <2>',
      stackTrace: 'test/a_test.dart 8:7',
    ),
    TestCase(
      suite: 'test/b_test.dart',
      name: 'new failure',
      status: TestStatus.errored,
      message: 'Bad state: boom',
    ),
    TestCase(
      suite: 'test/b_test.dart',
      name: 'later',
      status: TestStatus.skipped,
    ),
  ]);
  final earlier = TestRunResults.of(const [
    TestCase(
      suite: 'test/a_test.dart',
      name: 'a ok',
      status: TestStatus.passed,
    ),
    TestCase(
      suite: 'test/a_test.dart',
      name: 'old failure',
      status: TestStatus.failed,
    ),
  ]);
  return TestRunRecord(
    id: 'tst_$jobId',
    jobId: jobId,
    projectId: 'prj_1',
    branch: branch,
    appPath: appPath,
    baseline: baseline,
    createdAt: createdAt ?? DateTime.utc(2026, 10, 13, 9),
    results: results,
    diff: diffTestRuns(results, earlier, comparedTo: 'job_0'),
  );
}

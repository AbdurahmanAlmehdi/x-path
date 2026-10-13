import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/jobs/job_exceptions.dart';
import 'package:xp_engine/src/jobs/job_repository.dart';
import 'package:xp_engine/src/projects/project_exceptions.dart';
import 'package:xp_engine/src/projects/project_repository.dart';
import 'package:xp_engine/src/testing/test_run_exceptions.dart';
import 'package:xp_engine/src/testing/test_run_record.dart';
import 'package:xp_engine/src/testing/test_run_repository.dart';

/// A run with a page of its tests.
class TestRunPage {
  /// Creates a page.
  const new({
    required this.run,
    required this.total,
    required this.offset,
    required this.tests,
  });

  /// The run.
  final TestRunRecord run;

  /// How many tests matched, over all pages.
  final int total;

  /// Where the page starts among the matching tests.
  final int offset;

  /// The page.
  final List<TestCase> tests;
}

/// What clients can read of the test runs of the engine.
class TestRunService {
  /// Creates the service.
  const new({
    required this._runs,
    required this._jobs,
    required this._projects,
  });

  final TestRunRepository _runs;
  final JobRepository _jobs;
  final ProjectRepository _projects;

  /// The statuses listed unless a request asks for others.
  static const Set<TestStatus> defaultStatuses = {
    TestStatus.failed,
    TestStatus.errored,
  };

  /// The run of the job [jobId] with a page of the tests that ended as one of
  /// [statuses] (the failures by default), ordered by file and name.
  ///
  /// Throws a [JobNotFoundException] if there is no such job and a
  /// [TestRunNotFoundException] if it has no test run.
  Future<TestRunPage> forJob(
    String jobId, {
    Set<TestStatus> statuses = defaultStatuses,
    int limit = 200,
    int offset = 0,
  }) async {
    if (await _jobs.get(jobId) == null) throw JobNotFoundException(jobId);
    final run =
        await _runs.forJob(jobId) ?? (throw TestRunNotFoundException(jobId));
    final matching = [
      for (final test in run.results.tests)
        if (statuses.contains(test.status)) test,
    ];
    return TestRunPage(
      run: run,
      total: matching.length,
      offset: offset,
      tests: matching.skip(offset).take(limit).toList(),
    );
  }

  /// The current baseline of every app and branch of the project [projectId].
  ///
  /// Throws a [ProjectNotFoundException] if there is no such project.
  Future<List<TestRunRecord>> baselines(String projectId) async {
    if (await _projects.get(projectId) == null) {
      throw ProjectNotFoundException(projectId);
    }
    return await _runs.baselines(projectId);
  }
}

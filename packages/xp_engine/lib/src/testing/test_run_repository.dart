import 'package:xp_engine/src/testing/test_run_record.dart';

/// Where test runs are kept.
///
/// `xp_adapters` has the SQLite implementation.
abstract interface class TestRunRepository {
  /// Stores [run], replacing the run of the same job: a job has one.
  Future<void> save(TestRunRecord run);

  /// The run of the job [jobId], or `null`.
  Future<TestRunRecord?> forJob(String jobId);

  /// The latest baseline of the app at [appPath] on [branch] in the project
  /// [projectId], or `null` if none was recorded.
  Future<TestRunRecord?> baseline({
    required String projectId,
    required String appPath,
    required String branch,
  });

  /// The latest baseline of every app and branch of the project [projectId],
  /// ordered by app and branch.
  Future<List<TestRunRecord>> baselines(String projectId);
}

/// A [TestRunRepository] that forgets everything on exit.
class InMemoryTestRunRepository implements TestRunRepository {
  final _runs = <String, TestRunRecord>{};

  @override
  Future<void> save(TestRunRecord run) async => _runs[run.jobId] = run;

  @override
  Future<TestRunRecord?> forJob(String jobId) async => _runs[jobId];

  @override
  Future<TestRunRecord?> baseline({
    required String projectId,
    required String appPath,
    required String branch,
  }) async =>
      (await baselines(projectId))
          .where((run) => run.appPath == appPath && run.branch == branch)
          .firstOrNull;

  @override
  Future<List<TestRunRecord>> baselines(String projectId) async {
    final latest = <(String, String), TestRunRecord>{};
    for (final run in _runs.values) {
      if (run.projectId != projectId || !run.baseline) continue;
      final key = (run.appPath, run.branch);
      final known = latest[key];
      if (known == null || !run.createdAt.isBefore(known.createdAt)) {
        latest[key] = run;
      }
    }
    return latest.values.toList()..sort((a, b) {
      final byApp = a.appPath.compareTo(b.appPath);
      return byApp != 0 ? byApp : a.branch.compareTo(b.branch);
    });
  }
}

import 'package:xp_api/xp_api.dart';
import 'package:xp_repositories/src/session/engine_session.dart';
import 'package:xp_repositories/src/snapshot.dart';

/// The test runs of the engine of an [EngineSession] and the baselines they
/// are compared with (D-21).
class TestsRepository {
  /// Creates the repository.
  const new(this._session);

  /// How many failing tests [watchRun] lists at most: the engine's limit.
  static const maxListed = 1000;

  final EngineSession _session;

  /// The baselines of [projectId], one per app and branch, kept up to date by
  /// the test runs that become one.
  Stream<Snapshot<List<TestBaseline>>> watchBaselines(String projectId) =>
      _session.watch(
        key: 'test-baselines.$projectId',
        fetch: (client) => client.getTestBaselines(projectId),
        encode: (baselines) => [
          for (final baseline in baselines) baseline.toJson(),
        ],
        decode: (json) => [
          for (final baseline in json! as List<dynamic>)
            TestBaseline.fromJson(baseline as Map<String, dynamic>),
        ],
        refreshOn: (event) => switch (event) {
          TestRunCompleted(baseline: true, projectId: final project) =>
            project == projectId,
          _ => false,
        },
      );

  /// The test run of [jobId] with its failing tests (at most [maxListed];
  /// `total` says how many there are), kept up to date when the job runs its
  /// tests again.
  Stream<Snapshot<TestRunResponse>> watchRun(String jobId) => _session.watch(
    key: 'test-run.$jobId',
    fetch: (client) => client.getJobTests(jobId, limit: maxListed),
    encode: (response) => response.toJson(),
    decode: (json) => TestRunResponse.fromJson(json! as Map<String, dynamic>),
    refreshOn: (event) => event is TestRunCompleted && event.jobId == jobId,
  );

  /// The test runs of [projectId] that end from now on. The engine has no
  /// list of past runs: those before are reached through their job.
  Stream<TestRunCompleted> completedRuns(String projectId) => _session.events
      .where(
        (event) => event is TestRunCompleted && event.projectId == projectId,
      )
      .cast<TestRunCompleted>();
}

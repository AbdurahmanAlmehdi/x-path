import 'package:xp_api/xp_api.dart';
import 'package:xp_repositories/src/run_jobs.dart';
import 'package:xp_repositories/src/session/engine_session.dart';
import 'package:xp_repositories/src/snapshot.dart';

/// The runs and jobs of the engine of an [EngineSession], their logs and
/// artifacts.
class JobsRepository {
  /// Creates the repository.
  const new(this._session);

  final EngineSession _session;

  /// One job with its steps, kept up to date by its job and step events.
  Stream<Snapshot<Job>> watchJob(String id) => _session.watch(
    key: 'job.$id',
    fetch: (client) => client.getJob(id),
    encode: (job) => job.toJson(),
    decode: (json) => Job.fromJson(json! as Map<String, dynamic>),
    refreshOn: (event) => switch (event) {
      JobStateChanged(:final jobId) ||
      JobStepChanged(:final jobId) ||
      RunnerLeaseLost(:final jobId) => jobId == id,
      _ => false,
    },
  );

  /// One run with the state of each of its jobs, kept up to date by the job
  /// and approval events of its project.
  Stream<Snapshot<Run>> watchRun(String id) {
    String? projectId;
    return _session.watch(
      key: 'run.$id',
      fetch: (client) async {
        final run = await client.getRun(id);
        projectId = run.projectId;
        return run;
      },
      encode: (run) => run.toJson(),
      decode: (json) => Run.fromJson(json! as Map<String, dynamic>),
      refreshOn: (event) => switch (event) {
        JobStateChanged(projectId: final project) ||
        ApprovalRequested(projectId: final project) ||
        ApprovalDecided(projectId: final project) ||
        ApprovalExpired(projectId: final project) => project == projectId,
        _ => false,
      },
    );
  }

  /// One run with every one of its jobs and their steps, kept up to date by
  /// the events of those jobs and the approvals of its project: what the job
  /// view draws its pipeline graph from.
  Stream<Snapshot<RunJobs>> watchRunJobs(String id) {
    String? projectId;
    var jobIds = <String>{};
    return _session.watch(
      key: 'run-jobs.$id',
      fetch: (client) async {
        final run = await client.getRun(id);
        final jobs = [for (final job in run.jobs) await client.getJob(job.id)];
        projectId = run.projectId;
        jobIds = {for (final job in run.jobs) job.id};
        return RunJobs(run: run, jobs: jobs);
      },
      encode: (value) => value.toJson(),
      decode: (json) => RunJobs.fromJson(json! as Map<String, dynamic>),
      refreshOn: (event) => switch (event) {
        JobStateChanged(:final jobId) ||
        JobStepChanged(:final jobId) ||
        RunnerLeaseLost(:final jobId) => jobIds.contains(jobId),
        ApprovalRequested(projectId: final project) ||
        ApprovalDecided(projectId: final project) ||
        ApprovalExpired(projectId: final project) => project == projectId,
        _ => false,
      },
    );
  }

  /// Cancels [id].
  Future<Job> cancelJob(String id) =>
      _session.call((client) => client.cancelJob(id));

  /// Resumes [id] at its first unfinished step, or at [fromStep].
  Future<Job> resumeJob(String id, {int? fromStep}) =>
      _session.call((client) => client.resumeJob(id, fromStep: fromStep));

  /// Cancels every job of the run [id] that has not ended.
  Future<Run> cancelRun(String id) =>
      _session.call((client) => client.cancelRun(id));

  /// The log of [id] after line [after], live until the job ends.
  Stream<LogFrame> followLogs(String id, {int after = 0}) =>
      _session.client.followJobLogs(id, after: after);

  /// The artifacts of [jobId].
  Future<List<Artifact>> listArtifacts(String jobId) =>
      _session.call((client) => client.listJobArtifacts(jobId));
}

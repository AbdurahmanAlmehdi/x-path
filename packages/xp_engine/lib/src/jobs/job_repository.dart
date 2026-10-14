import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/jobs/job_record.dart';
import 'package:xp_engine/src/toolchain/job_tools.dart';

/// Where jobs and their steps are kept.
///
/// `xp_adapters` has the SQLite implementation.
abstract interface class JobRepository {
  /// Stores a new job with its steps, which are numbered by their position.
  Future<void> create(JobRecord job, List<StepRecord> steps);

  /// The job [id], or `null`.
  Future<JobRecord?> get(String id);

  /// The steps of the job [jobId], in order.
  Future<List<StepRecord>> steps(String jobId);

  /// The jobs in one of [states], oldest first.
  Future<List<JobRecord>> list({required Set<JobState> states});

  /// The jobs of the run [runId], by stage, in the order they were made.
  Future<List<JobRecord>> forRun(String runId);

  /// Replaces the stored job that has the id of [job].
  Future<void> updateJob(JobRecord job);

  /// Records the versions of the tools the job [jobId] runs with (D-20),
  /// replacing any recorded before.
  ///
  /// Throws a `StateError` if there is no such job.
  Future<void> saveTools(String jobId, JobTools tools);

  /// The tool versions recorded for the job [jobId], or `null` if none were,
  /// or there is no such job.
  Future<JobTools?> tools(String jobId);

  /// Replaces the stored step with the job and ordinal of [step].
  Future<void> updateStep(StepRecord step);
}

/// A [JobRepository] that forgets everything on exit.
class InMemoryJobRepository implements JobRepository {
  final _jobs = <String, JobRecord>{};
  final _steps = <String, List<StepRecord>>{};
  final _tools = <String, JobTools>{};

  @override
  Future<void> create(JobRecord job, List<StepRecord> steps) async {
    if (_jobs.containsKey(job.id)) throw StateError('Job ${job.id} exists.');
    _jobs[job.id] = job;
    _steps[job.id] = List.of(steps);
  }

  @override
  Future<JobRecord?> get(String id) async => _jobs[id];

  @override
  Future<List<StepRecord>> steps(String jobId) async =>
      List.of(_steps[jobId] ?? const []);

  @override
  Future<List<JobRecord>> list({required Set<JobState> states}) async => [
    for (final job in _jobs.values)
      if (states.contains(job.state)) job,
  ];

  @override
  Future<List<JobRecord>> forRun(String runId) async {
    final jobs = _jobs.values.where((job) => job.runId == runId).toList();
    // `sort` is not stable, and jobs are in the order they were made.
    return [
      for (final (_, job)
          in [for (final (index, job) in jobs.indexed) (index, job)]..sort(
            (a, b) => a.$2.stage != b.$2.stage
                ? a.$2.stage.compareTo(b.$2.stage)
                : a.$1.compareTo(b.$1),
          ))
        job,
    ];
  }

  @override
  Future<void> updateJob(JobRecord job) async {
    if (!_jobs.containsKey(job.id)) throw StateError('No job ${job.id}.');
    _jobs[job.id] = job;
  }

  @override
  Future<void> saveTools(String jobId, JobTools tools) async {
    if (!_jobs.containsKey(jobId)) throw StateError('No job $jobId.');
    _tools[jobId] = tools;
  }

  @override
  Future<JobTools?> tools(String jobId) async => _tools[jobId];

  @override
  Future<void> updateStep(StepRecord step) async {
    final steps = _steps[step.jobId];
    if (steps == null || step.ordinal >= steps.length) {
      throw StateError('No step ${step.ordinal} in job ${step.jobId}.');
    }
    steps[step.ordinal] = step;
  }
}

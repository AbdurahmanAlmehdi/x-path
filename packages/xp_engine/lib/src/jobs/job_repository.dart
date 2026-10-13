import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/jobs/job_record.dart';

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

  /// Replaces the stored job that has the id of [job].
  Future<void> updateJob(JobRecord job);

  /// Replaces the stored step with the job and ordinal of [step].
  Future<void> updateStep(StepRecord step);
}

/// A [JobRepository] that forgets everything on exit.
class InMemoryJobRepository implements JobRepository {
  final _jobs = <String, JobRecord>{};
  final _steps = <String, List<StepRecord>>{};

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
  Future<void> updateJob(JobRecord job) async {
    if (!_jobs.containsKey(job.id)) throw StateError('No job ${job.id}.');
    _jobs[job.id] = job;
  }

  @override
  Future<void> updateStep(StepRecord step) async {
    final steps = _steps[step.jobId];
    if (steps == null || step.ordinal >= steps.length) {
      throw StateError('No step ${step.ordinal} in job ${step.jobId}.');
    }
    steps[step.ordinal] = step;
  }
}

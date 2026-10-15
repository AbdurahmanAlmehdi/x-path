import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';

/// A run with every one of its jobs, steps included.
class RunJobs extends Equatable {
  /// Creates the pair.
  const new({required this.run, required this.jobs});

  /// Reads the pair from its cached JSON form.
  factory fromJson(Map<String, dynamic> json) => RunJobs(
    run: Run.fromJson(json['run'] as Map<String, dynamic>),
    jobs: [
      for (final job in json['jobs'] as List<dynamic>)
        Job.fromJson(job as Map<String, dynamic>),
    ],
  );

  /// The run.
  final Run run;

  /// Its jobs, in the order of the run.
  final List<Job> jobs;

  /// The job [id], if it is one of [jobs].
  Job? job(String id) {
    for (final job in jobs) {
      if (job.id == id) return job;
    }
    return null;
  }

  /// The cached JSON form.
  Map<String, dynamic> toJson() => {
    'run': run.toJson(),
    'jobs': [for (final job in jobs) job.toJson()],
  };

  @override
  List<Object?> get props => [run, jobs];
}

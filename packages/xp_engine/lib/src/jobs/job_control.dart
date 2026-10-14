import 'package:xp_api/xp_api.dart';

/// What a client of the engine does with a job that exists: look at it, cancel
/// it, run it again.
///
/// `JobRunner` does it for one job; the `Scheduler` does it and also decides
/// when the jobs that wait may start, so the HTTP routes ask it.
abstract interface class JobControl {
  /// The job [id] with its steps.
  ///
  /// Throws a `JobNotFoundException` if there is none.
  Future<Job> get(String id);

  /// Cancels the job [id] and returns it once it has ended.
  ///
  /// Throws a `JobNotFoundException` if there is none and a
  /// `JobStateException` if it ended already.
  Future<Job> cancel(String id);

  /// Runs the job [id] again, at its first unfinished step or at [fromStep],
  /// and returns it, running.
  ///
  /// Throws a `JobNotFoundException`, a `JobStateException` or a
  /// `JobInvalidException` as `JobRunner.resume` does.
  Future<Job> resume(String id, {int? fromStep});
}

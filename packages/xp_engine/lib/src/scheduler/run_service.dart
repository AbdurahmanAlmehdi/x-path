import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/jobs/job_control.dart';
import 'package:xp_engine/src/jobs/job_repository.dart';
import 'package:xp_engine/src/scheduler/run_record.dart';

/// A run cannot be found or changed.
class RunException implements Exception {
  /// Creates the exception with a [message] for the owner.
  const new(this.message);

  /// What is wrong.
  final String message;

  @override
  String toString() => 'RunException: $message';
}

/// There is no such run.
class RunNotFoundException extends RunException {
  /// Creates the exception.
  const new(this.id) : super('There is no run $id.');

  /// The id that was asked for.
  final String id;

  @override
  String toString() => 'RunNotFoundException: $message';
}

/// The run has ended, so it cannot be cancelled.
class RunStateException extends RunException {
  /// Creates the exception.
  const new(super.message);

  @override
  String toString() => 'RunStateException: $message';
}

/// Shows and cancels runs.
class RunService {
  /// Creates the service. Jobs are cancelled through [_control], so that the
  /// scheduler hears about it.
  new({required this._runs, required this._jobs, required this._control});

  final RunRepository _runs;
  final JobRepository _jobs;
  final JobControl _control;

  /// The run [id] with the state of its jobs.
  ///
  /// Throws a [RunNotFoundException] if there is none.
  Future<Run> get(String id) async {
    final run = await _runs.get(id) ?? (throw RunNotFoundException(id));
    return run.toRun(await _jobs.forRun(id));
  }

  /// Cancels every job of the run [id] that has not ended: running jobs have
  /// their process groups stopped, queued and waiting ones are cancelled at
  /// once. Returns the run.
  ///
  /// Throws a [RunNotFoundException] if there is none and a
  /// [RunStateException] if every job of it ended already.
  Future<Run> cancel(String id) async {
    final run = await _runs.get(id) ?? (throw RunNotFoundException(id));
    final open = [
      for (final job in await _jobs.forRun(id))
        if (!job.state.isFinished) job,
    ];
    if (open.isEmpty) {
      throw RunStateException('Run $id has ended: every job of it has.');
    }
    for (final job in open) {
      await _control.cancel(job.id);
    }
    return run.toRun(await _jobs.forRun(id));
  }
}

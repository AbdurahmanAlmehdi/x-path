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

  /// The runs, newest first: of [projectId], of [workflowId] and in [state]
  /// when given, dispatched before the run [before] when given, at most
  /// [limit]; and the `before` of the next page when there may be one.
  ///
  /// Throws a [RunNotFoundException] if there is no run [before].
  Future<RunsResponse> list({
    String? projectId,
    String? workflowId,
    RunState? state,
    String? before,
    int limit = 50,
  }) async {
    if (before != null && await _runs.get(before) == null) {
      throw RunNotFoundException(before);
    }
    final found = <Run>[];
    var cursor = before;
    while (found.length < limit) {
      // A state is known once a run's jobs are read, so with one the runs
      // are read a page at a time until enough of them are in it.
      final asked = state == null ? limit - found.length : 100;
      final page = await _runs.list(
        projectId: projectId,
        workflowId: workflowId,
        before: cursor,
        limit: asked,
      );
      for (final record in page) {
        final run = record.toRun(await _jobs.forRun(record.id));
        if (state == null || run.state == state) found.add(run);
        if (found.length == limit) break;
      }
      if (page.length < asked) break;
      cursor = page.last.id;
    }
    return RunsResponse(
      found,
      next: found.length == limit ? found.last.id : null,
    );
  }

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

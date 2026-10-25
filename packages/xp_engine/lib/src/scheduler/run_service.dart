import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/jobs/job_control.dart';
import 'package:xp_engine/src/jobs/job_repository.dart';
import 'package:xp_engine/src/scheduler/run_record.dart';

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
  ///
  /// A list in a state reads the runs [_statePage] at a time, at most
  /// [_statePages] pages per call.
  new({
    required this._runs,
    required this._jobs,
    required this._control,
    this._statePage = 100,
    this._statePages = 10,
  });

  final RunRepository _runs;
  final JobRepository _jobs;
  final JobControl _control;
  final int _statePage;
  final int _statePages;

  /// The runs, newest first: of [projectId], of [workflowId] and in [state]
  /// when given, dispatched before the run [before] when given, at most
  /// [limit]; and the `before` of the next page when there may be one. In a
  /// [state], a page may come back short once enough runs were read: its
  /// `next` goes on from the last run read.
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
    String? next;
    for (var pages = 1; found.length < limit; pages++) {
      // A state is known once a run's jobs are read, so with one the runs
      // are read a page at a time until enough of them are in it.
      final asked = state == null ? limit - found.length : _statePage;
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
      if (state != null && pages == _statePages) {
        next = cursor;
        break;
      }
    }
    return RunsResponse(
      found,
      next: found.length == limit ? found.last.id : next,
    );
  }

  /// The run [id] with the state of its jobs.
  ///
  /// Throws a [RunNotFoundException] if there is none.
  Future<Run> get(String id) async {
    final run = await _runs.get(id) ?? (throw RunNotFoundException(id));
    return run.toRun(await _jobs.forRun(id));
  }

  /// Runs the failed jobs of the run [id] again, each from the step that
  /// failed: what the jobs before made (their artifacts, the commit) is
  /// used as it is, nothing is built again that did not fail. The later
  /// stages then go on. A failed, interrupted or waiting-for-resume job is
  /// run again; a cancelled one is not. Returns the run.
  ///
  /// Throws a [RunNotFoundException] if there is none and a
  /// [RunStateException] if no job of it failed.
  Future<Run> rerunFailed(String id) async {
    final run = await _runs.get(id) ?? (throw RunNotFoundException(id));
    const again = {
      JobState.failed,
      JobState.interrupted,
      JobState.waitingForResume,
    };
    final failed = [
      for (final job in await _jobs.forRun(id))
        if (again.contains(job.state)) job,
    ];
    if (failed.isEmpty) {
      throw RunStateException('Run $id has no failed job to run again.');
    }
    for (final job in failed) {
      await _control.resume(job.id);
    }
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

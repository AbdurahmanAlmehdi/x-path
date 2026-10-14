import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/clock/clock.dart';
import 'package:xp_engine/src/jobs/job_repository.dart';
import 'package:xp_engine/src/jobs/secret_file_store.dart';
import 'package:xp_engine/src/process/process_supervisor.dart';
import 'package:xp_engine/src/repositories/event_log.dart';

/// What [JobRecovery.recover] found.
class RecoveryReport {
  /// Creates a report.
  const new({this.resumable = const [], this.waiting = const []});

  /// The jobs that can simply run again: the step that was running has no
  /// side effects.
  final List<String> resumable;

  /// The jobs that wait for an explicit resume because a step with side
  /// effects was running (D-18).
  final List<String> waiting;
}

/// Cleans up after an engine that stopped while jobs ran (D-18).
///
/// For every job left `running`: the process group recorded for its running
/// step is stopped (`SIGTERM`, grace, `SIGKILL`; ADR 0003), the step and the
/// job are marked `interrupted` (the job `waiting_for_resume` if the step has
/// side effects), and the secret files of the job are deleted.
///
/// A recorded process group id can in theory belong to an unrelated process
/// group by now, if the machine rebooted and the numbers were reused. The
/// engine only signals groups that are still alive, never one below 2, and
/// forgets a group as soon as its step ends, so only the steps that were
/// running when the engine stopped have one.
class JobRecovery {
  /// Creates the recovery.
  new({
    required this._jobs,
    required this._killer,
    required this._secretFiles,
    required this._events,
    required this._clock,
  });

  final JobRepository _jobs;
  final ProcessGroupKiller _killer;
  final SecretFileStore _secretFiles;
  final EventLog _events;
  final Clock _clock;

  /// Recovers every job that is left `running`.
  Future<RecoveryReport> recover() async {
    final resumable = <String>[];
    final waiting = <String>[];
    for (final job in await _jobs.list(states: {JobState.running})) {
      var sideEffect = false;
      for (final step in await _jobs.steps(job.id)) {
        if (step.state != StepState.running) continue;
        final pgid = step.pgid;
        if (pgid != null) await _killer.stop(pgid);
        sideEffect = sideEffect || step.sideEffect;
        await _jobs.updateStep(
          step.copyWith(
            state: StepState.interrupted,
            message: 'The engine stopped while the step was running.',
            pgid: null,
            finishedAt: _clock.now(),
          ),
        );
        _events.append(
          JobStepChanged(
            jobId: job.id,
            ordinal: step.ordinal,
            kind: step.kind,
            state: StepState.interrupted,
          ),
        );
      }
      final state = sideEffect
          ? JobState.waitingForResume
          : JobState.interrupted;
      // A job that ran on a remote runner holds no lease any more: the
      // runner's next hello is answered with a cancel.
      await _jobs.updateJob(
        job.copyWith(
          state: state,
          runnerId: null,
          leaseUntil: null,
          message: 'The engine stopped while the job was running.',
          finishedAt: _clock.now(),
        ),
      );
      _events.append(
        JobStateChanged(jobId: job.id, projectId: job.projectId, state: state),
      );
      await _secretFiles.deleteAll(job.id);
      (sideEffect ? waiting : resumable).add(job.id);
    }
    return RecoveryReport(resumable: resumable, waiting: waiting);
  }
}

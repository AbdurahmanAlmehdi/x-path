import 'dart:async';

import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/jobs/job_control.dart';
import 'package:xp_engine/src/jobs/job_exceptions.dart';
import 'package:xp_engine/src/jobs/job_record.dart';
import 'package:xp_engine/src/jobs/job_repository.dart';
import 'package:xp_engine/src/jobs/job_runner.dart';
import 'package:xp_engine/src/repositories/event_log.dart';
import 'package:xp_engine/src/scheduler/capability.dart';
import 'package:xp_engine/src/scheduler/paired_runners.dart';
import 'package:xp_engine/src/scheduler/run_record.dart';
import 'package:xp_engine/src/scheduler/scheduler_runner.dart';

/// Where a dry run of a dispatch places a job: whether the engine can run
/// it, the connected runner it can go to, and why it would wait when
/// neither can.
typedef JobPlacement = ({bool local, String? runner, String? waitReason});

/// Decides which queued job starts, where, and when (D-11, D-19).
///
/// The jobs of dispatched runs wait in the database in state `queued`. Each
/// time something changes (a run is dispatched, a job ends or is cancelled,
/// a gate is approved, the engine starts) the scheduler makes one pass over
/// the open runs and starts what may start:
///
/// - **Stages.** The jobs of a stage start when every job of the stages
///   before it succeeded. A failed or cancelled job holds the later stages
///   back (they stay queued) until it is resumed and succeeds.
/// - **The project lock.** A run of a workflow with `lock: project` (a
///   production release or patch) starts only when no other such run of the
///   project is under way. It waits in line: runs are served in the order they
///   were dispatched, and a later run never overtakes an earlier one that
///   waits for the lock. Dev builds have no lock.
/// - **Slots.** A runner runs at most `slots` jobs at once, and only one job
///   that needs `ios-sign` (the keychain and Xcode cannot share).
/// - **Capabilities.** A job goes to a runner that can do everything it needs.
/// - **Engine-only steps.** A runner may refuse a job by its steps: a remote
///   runner never gets a job with an upload or another step that needs what
///   only the engine has (D-09, `RemoteStepPolicy`).
/// - **Placement.** The local runner is preferred: a job that fits the engine
///   and has a free slot there runs on the engine, and a remote runner takes
///   what the engine cannot do or has no slot for. Among remote runners the
///   least loaded one (its running jobs per slot) goes first, then the one
///   that connected first.
/// - **Order.** Runs are served oldest first, their jobs in stage and creation
///   order. A job that cannot start (no free slot, a locked project) does not
///   hold up the jobs behind it that can. Nothing depends on the clock or on
///   chance, so the same state always gives the same pass.
///
/// A queued job that waits says why in its `message`; when no connected
/// runner can do it, the message names the paired runners that could and are
/// offline. A job that reaches a
/// gate stops in `waiting_for_approval` and holds no slot; whoever decides the
/// gate calls [resumeWaiting] and the job takes its turn again.
class Scheduler implements JobControl {
  /// Creates the scheduler over the job runner, its records and the runs.
  new({
    required this._runner,
    required this._records,
    required this._runs,
    required this._events,
    required Iterable<SchedulerRunner> runners,
    this.onError,
  }) : _targets = List.of(runners);

  /// Hears about failures of a pass.
  final void Function(Object error, StackTrace stackTrace)? onError;

  final JobRunner _runner;
  final JobRepository _records;
  final RunRepository _runs;
  final EventLog _events;
  final List<SchedulerRunner> _targets;
  final _watched = <String>{};
  Future<void> _tail = Future.value();
  Future<void>? _queued;
  var _stopped = false;

  /// The runners jobs can go to.
  List<SchedulerRunner> get runners => List.unmodifiable(_targets);

  /// Adds a runner. The next pass can use it.
  void addRunner(SchedulerRunner runner) => _targets.add(runner);

  /// Removes a runner. Jobs that run on it are not touched.
  void removeRunner(String id) =>
      _targets.removeWhere((runner) => runner.id == id);

  /// The place where jobs that run on remote runners are cancelled, if
  /// there is one. Set once, after the runners hub exists: the hub needs the
  /// scheduler, so the scheduler cannot take it in its constructor.
  RemoteJobs? remoteJobs;

  /// The paired runners, to name the offline ones that could take a job no
  /// connected runner can do. Set once, like [remoteJobs].
  PairedRunners? pairedRunners;

  /// Stops starting jobs: the engine is shutting down.
  void stop() => _stopped = true;

  // ------------------------------------------------------------- JobControl

  @override
  Future<Job> get(String id) => _runner.get(id);

  @override
  Future<Job> cancel(String id) async {
    final remote = remoteJobs;
    final job = remote != null && await remote.cancel(id)
        ? await get(id)
        : await _runner.cancel(id);
    await pump();
    return job;
  }

  /// Runs the job [id] again when the scheduler has a place for it.
  ///
  /// A dispatched job goes back in the queue and takes its turn (so a
  /// production release cannot be resumed beside another one, and a resume
  /// cannot overfill a runner); the answer is the job, `queued` if it waits.
  /// Any other job is resumed at once, as `JobRunner.resume` does.
  ///
  /// Throws what `JobRunner.resume` throws.
  @override
  Future<Job> resume(String id, {int? fromStep}) async {
    final record = await _records.get(id);
    if (record == null) throw JobNotFoundException(id);
    if (record.runId == null) {
      return await _runner.resume(id, fromStep: fromStep);
    }
    final queued = await _runner.requeue(id, fromStep: fromStep);
    await pump();
    return await _runner.get(queued.id);
  }

  /// Puts the jobs of the project [projectId] that wait for an approval back
  /// in the queue: a gate was decided, so each asks again. A job whose gate is
  /// still undecided waits again.
  ///
  /// The `ApprovalService` calls it when an approval is decided or expires,
  /// and when a gate is turned off.
  Future<void> resumeWaiting({String? projectId}) async {
    final waiting = await _records.list(states: {JobState.waitingForApproval});
    for (final job in waiting) {
      if (job.runId == null ||
          (projectId != null && job.projectId != projectId)) {
        continue;
      }
      try {
        await _runner.requeue(job.id);
      } on JobException {
        // Cancelled since the list was read: nothing to ask again.
      }
    }
    await pump();
  }

  // ------------------------------------------------------------------ pass

  /// Starts what may start. Passes never overlap, and a request that comes
  /// while another is waiting to begin shares it.
  Future<void> pump() {
    final waiting = _queued;
    if (waiting != null) return waiting;
    late final Future<void> pass;
    pass = _tail.then((_) {
      _queued = null;
      return _pass();
    });
    _queued = pass;
    _tail = pass.then<void>((_) {}, onError: (_, _) {});
    return pass;
  }

  Future<void> _pass() async {
    if (_stopped) return;
    try {
      await _schedule();
    } on Object catch (error, stackTrace) {
      onError?.call(error, stackTrace);
    }
  }

  Future<void> _schedule() async {
    const open = {
      JobState.queued,
      JobState.running,
      JobState.interrupted,
      JobState.waitingForResume,
      JobState.waitingForApproval,
    };
    final openJobs = await _records.list(states: open);
    // A run that holds the project is looked at even when all its jobs ended,
    // to let go of it.
    final runIds = {
      for (final job in openJobs)
        if (job.runId != null) job.runId!,
      for (final run in await _runs.held()) run.id,
    };
    final snapshots = <_Snapshot>[];
    for (final runId in runIds) {
      final run = await _runs.get(runId);
      if (run == null) continue;
      snapshots.add(_Snapshot(run, await _records.forRun(runId)));
    }
    snapshots.sort((a, b) {
      final byTime = a.run.createdAt.compareTo(b.run.createdAt);
      return byTime != 0 ? byTime : a.run.id.compareTo(b.run.id);
    });

    final used = <String, int>{};
    final signing = <String>{};
    for (final job in openJobs) {
      if (job.state != JobState.running) continue;
      final runnerId = job.runnerId ?? localRunnerId;
      used[runnerId] = (used[runnerId] ?? 0) + 1;
      if (job.capabilities.contains(Capability.iosSign.wire)) {
        signing.add(runnerId);
      }
    }
    // A run that held the project and failed, was cancelled or finished lets
    // go of it. One whose failed job is resumed asks for it again.
    final runs = <_Snapshot>[];
    for (var snapshot in snapshots) {
      final run = snapshot.run;
      if (run.lockHeld && snapshot.isEnded) {
        await _runs.setLockHeld(run.id, held: false);
        snapshot = _Snapshot(run.withLockHeld(held: false), snapshot.jobs);
      }
      runs.add(snapshot);
    }
    final holders = {
      for (final snapshot in runs)
        if (snapshot.run.lockHeld) snapshot.run.projectId: snapshot.run.id,
    };
    final waitingOn = <String, String>{};
    // Read once per pass, and only when a job waits for a capability.
    Future<List<PairedRunner>>? paired;
    Future<List<PairedRunner>> readPaired() => paired ??=
        pairedRunners?.pairedRunners() ?? Future.value(const <PairedRunner>[]);

    for (final snapshot in runs) {
      final queued = snapshot.nextJobs;
      if (queued.isEmpty) {
        await _explainBlockedJobs(snapshot);
        continue;
      }
      final run = snapshot.run;
      if (run.locksProject && !run.lockHeld) {
        final blocker = holders[run.projectId] ?? waitingOn[run.projectId];
        if (blocker != null) {
          for (final job in queued) {
            await _note(
              job,
              'Waiting for run $blocker to finish: only one production '
              'release or patch of a project runs at a time.',
            );
          }
          continue;
        }
        // First in line for the lock, even if its jobs cannot start yet.
        waitingOn[run.projectId] = run.id;
      }
      for (final job in queued) {
        final kinds = [
          for (final step in await _records.steps(job.id)) step.kind,
        ];
        final runner = _place(job, kinds, used, signing);
        if (runner == null) {
          await _note(
            job,
            await _whyNoRunner(job, kinds, used, signing, readPaired),
          );
          continue;
        }
        if (await _launch(runner, job)) {
          used[runner.id] = (used[runner.id] ?? 0) + 1;
          if (job.capabilities.contains(Capability.iosSign.wire)) {
            signing.add(runner.id);
          }
          if (run.locksProject && !holders.containsKey(run.projectId)) {
            holders[run.projectId] = run.id;
            await _runs.setLockHeld(run.id, held: true);
          }
        }
      }
    }
  }

  /// Tells why the queued jobs of a run that has none ready wait.
  Future<void> _explainBlockedJobs(_Snapshot snapshot) async {
    final blocking = snapshot.blockingJob;
    if (blocking == null) return;
    for (final job in snapshot.jobs) {
      if (job.state != JobState.queued) continue;
      await _note(
        job,
        'Waiting for job ${blocking.name ?? blocking.id} '
        '(${blocking.state.wire}) of stage ${blocking.stage} to succeed.',
      );
    }
  }

  SchedulerRunner? _place(
    JobRecord job,
    List<String> kinds,
    Map<String, int> used,
    Set<String> signing,
  ) {
    final needs = _needs(job);
    SchedulerRunner? best;
    var bestLoad = 0.0;
    for (final runner in _targets) {
      if (!runner.capabilities.containsAll(needs) || !runner.accepts(kinds)) {
        continue;
      }
      final running = used[runner.id] ?? 0;
      if (running >= runner.slots) continue;
      if (needs.contains(Capability.iosSign) && signing.contains(runner.id)) {
        continue;
      }
      // The engine first: it has the job's worktree, the secrets and the
      // stores at hand.
      if (runner.id == localRunnerId) return runner;
      final load = running / runner.slots;
      if (best == null || load < bestLoad) {
        best = runner;
        bestLoad = load;
      }
    }
    return best;
  }

  /// Where a job that needs [capabilities] and is made of steps of [kinds]
  /// could start, without queueing it (a dry run, UX-01): whether the engine
  /// can run it, the connected runner it can go to (by name), and why it
  /// would wait when neither can. Free slots are not counted: they change
  /// before the job's stage starts.
  Future<JobPlacement> placement(
    List<String> capabilities,
    List<String> kinds,
  ) async {
    final needs = {for (final wire in capabilities) ?Capability.fromWire(wire)};
    final able = [
      for (final runner in _targets)
        if (runner.capabilities.containsAll(needs) && runner.accepts(kinds))
          runner,
    ];
    final paired =
        await (pairedRunners?.pairedRunners() ??
            Future.value(const <PairedRunner>[]));
    final local = able.any((runner) => runner.id == localRunnerId);
    final remote = able.where((runner) => runner.id != localRunnerId);
    if (local || remote.isNotEmpty) {
      final id = remote.firstOrNull?.id;
      return (
        local: local,
        runner: id == null
            ? null
            : paired.where((runner) => runner.id == id).firstOrNull?.name ?? id,
        waitReason: null,
      );
    }
    return (
      local: false,
      runner: null,
      waitReason: await _cannotRun(needs, kinds, () async => paired),
    );
  }

  /// Why no connected runner can ever take a job that needs [needs] and is
  /// made of steps of [kinds]; `null` when one can.
  Future<String?> _cannotRun(
    Set<Capability> needs,
    List<String> kinds,
    Future<List<PairedRunner>> Function() paired,
  ) async {
    final capable = _targets
        .where((runner) => runner.capabilities.containsAll(needs))
        .toList();
    if (capable.isEmpty && needs.isEmpty) return 'No runner is connected.';
    if (capable.isEmpty) {
      final wires = needs.map((c) => c.wire).join(', ');
      final offline = [
        for (final runner in await paired())
          if (!runner.connected && runner.capabilities.containsAll(needs))
            _offline(runner, wires),
      ];
      if (offline.isEmpty) return 'No runner can do $wires.';
      return 'No connected runner can do $wires. ${offline.join(' ')}';
    }
    if (!capable.any((runner) => runner.accepts(kinds))) {
      final engineOnly = {
        for (final kind in kinds)
          if (!capable.any((runner) => runner.accepts([kind]))) kind,
      }.toList()..sort();
      return 'Only the engine runs ${engineOnly.join(', ')}, and the engine '
          'cannot do ${needs.map((c) => c.wire).join(', ')}.';
    }
    return null;
  }

  Future<String> _whyNoRunner(
    JobRecord job,
    List<String> kinds,
    Map<String, int> used,
    Set<String> signing,
    Future<List<PairedRunner>> Function() paired,
  ) async {
    final needs = _needs(job);
    if (await _cannotRun(needs, kinds, paired) case final reason?) {
      return reason;
    }
    final accepting = _targets
        .where(
          (runner) =>
              runner.capabilities.containsAll(needs) && runner.accepts(kinds),
        )
        .toList();
    if (needs.contains(Capability.iosSign) &&
        accepting.every((runner) => signing.contains(runner.id))) {
      return 'Waiting for the ios-sign job that runs now: one at a time.';
    }
    return 'Waiting for a free slot on '
        '${accepting.map((runner) => runner.id).join(', ')}.';
  }

  static String _offline(PairedRunner runner, String wires) {
    final since = runner.lastSeen;
    return '${runner.name} offers $wires; offline'
        '${since == null ? '' : ' since ${_at(since)}'}.';
  }

  /// [time] in UTC to the minute, for example `2026-10-22 14:02 UTC`.
  static String _at(DateTime time) {
    final utc = time.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${utc.year}-${two(utc.month)}-${two(utc.day)} '
        '${two(utc.hour)}:${two(utc.minute)} UTC';
  }

  Set<Capability> _needs(JobRecord job) => {
    for (final wire in job.capabilities) ?Capability.fromWire(wire),
  };

  Future<bool> _launch(SchedulerRunner runner, JobRecord job) async {
    try {
      await runner.launch(job.id);
    } on JobException {
      // Cancelled or resumed by someone else since the pass began.
      return false;
    }
    if (_watched.add(job.id)) {
      unawaited(
        runner.whenFinished(job.id).whenComplete(() {
          _watched.remove(job.id);
          unawaited(pump());
        }),
      );
    }
    return true;
  }

  /// Records why a queued job waits, once.
  Future<void> _note(JobRecord job, String message) async {
    if (job.message == message) return;
    final current = await _records.get(job.id);
    if (current == null || current.state != JobState.queued) return;
    await _records.updateJob(current.copyWith(message: message));
    _events.append(
      JobStateChanged(
        jobId: job.id,
        projectId: job.projectId,
        state: JobState.queued,
      ),
    );
  }
}

/// A run and its jobs, as one pass of the scheduler sees them.
class _Snapshot {
  const new(this.run, this.jobs);

  final RunRecord run;
  final List<JobRecord> jobs;

  RunState get state => deriveRunState(jobs.map((job) => job.state));

  /// Whether the run failed, was cancelled or succeeded.
  bool get isEnded =>
      state == RunState.failed ||
      state == RunState.cancelled ||
      state == RunState.succeeded;

  /// The stage the run is in: the first with a job that has not succeeded.
  int? get currentStage {
    for (final job in jobs) {
      if (job.state != JobState.succeeded) return job.stage;
    }
    return null;
  }

  /// The queued jobs that may start now: those of the current stage.
  List<JobRecord> get nextJobs {
    final stage = currentStage;
    if (stage == null) return const [];
    final inStage = jobs.where((job) => job.stage == stage);
    // A failed or cancelled job holds the stage: its siblings still run, but
    // none that is queued starts beside it (a run that failed stops).
    if (inStage.any(
      (job) => job.state == JobState.failed || job.state == JobState.cancelled,
    )) {
      return const [];
    }
    return [
      for (final job in inStage)
        if (job.state == JobState.queued) job,
    ];
  }

  /// The job that keeps the queued jobs of the run from starting, if one does.
  JobRecord? get blockingJob {
    final stage = currentStage;
    if (stage == null) return null;
    return jobs
        .where(
          (job) =>
              job.stage == stage &&
              (job.state == JobState.failed || job.state == JobState.cancelled),
        )
        .firstOrNull;
  }
}

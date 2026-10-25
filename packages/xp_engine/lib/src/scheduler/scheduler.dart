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
/// - **Slots.** A runner runs at most `slots` jobs at once, and only one iOS
///   job: one that needs `ios-sign` or `ios-linux` (the keychain and Xcode,
///   or omarchy-apple-dev's toolchain, cannot share).
/// - **Capabilities.** A job goes to a runner that meets every need of it: a
///   capability, or any of several (`ios-sign|ios-linux`, ADR 0014).
/// - **Engine-only steps.** A runner may refuse a job by its steps: a remote
///   runner never gets a job with an upload or another step that needs what
///   only the engine has (D-09, `RemoteStepPolicy`).
/// - **Placement.** A runner that meets an any-of need with the capability
///   it prefers goes first: a Mac before a Linux runner for an iOS build when
///   both are free. Then the local runner is preferred: a job that fits the
///   engine and has a free slot there runs on the engine, and a remote runner
///   takes what the engine cannot do or has no slot for. Among remote runners
///   the least loaded one (its running jobs per slot) goes first, then the
///   one that connected first.
/// - **Order.** Runs are served oldest first, their jobs in stage and creation
///   order. A job that cannot start (no free slot, a locked project) does not
///   hold up the jobs behind it that can. Nothing depends on the clock or on
///   chance, so the same state always gives the same pass.
///
/// A queued job that waits says why in its `message`; when no connected
/// runner can do it, the message names the paired runners that could and are
/// offline, and a job the planner narrowed to `ios-sign` says why Linux was
/// ruled out. A job that reaches a
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

  /// Whether the engine or a paired runner, online or not, meets every one
  /// of [needs]: a job that none does fails when it is dispatched instead of
  /// waiting for good.
  Future<bool> couldRun(List<CapabilityNeed> needs) async {
    bool meets(Set<Capability> offered) =>
        needs.every((need) => need.rankFor(offered) != null);
    if (_targets.any((runner) => meets(runner.capabilities))) return true;
    final paired = await pairedRunners?.pairedRunners() ?? const [];
    return paired.any((runner) => meets(runner.capabilities));
  }

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
      if (_isIos(job)) signing.add(runnerId);
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
          if (_isIos(job)) signing.add(runner.id);
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
    final ios = _isIos(job);
    SchedulerRunner? best;
    (int, double)? bestScore;
    for (final runner in _targets) {
      final rank = _rank(needs, runner.capabilities);
      if (rank == null || !runner.accepts(kinds)) continue;
      final running = used[runner.id] ?? 0;
      if (running >= runner.slots) continue;
      if (ios && signing.contains(runner.id)) continue;
      // The preferred capability first (a Mac for an iOS build), then the
      // engine: it has the job's worktree, the secrets and the stores at
      // hand. Then the least loaded runner.
      final score = (
        rank,
        runner.id == localRunnerId ? -1.0 : running / runner.slots,
      );
      if (bestScore == null ||
          score.$1 < bestScore.$1 ||
          (score.$1 == bestScore.$1 && score.$2 < bestScore.$2)) {
        best = runner;
        bestScore = score;
      }
    }
    return best;
  }

  /// How well [offered] meets [needs]: the sum of the ranks of the
  /// capabilities it meets them with (0 when it offers every preferred one),
  /// or `null` when it misses one.
  static int? _rank(List<CapabilityNeed> needs, Set<Capability> offered) {
    var sum = 0;
    for (final need in needs) {
      final rank = need.rankFor(offered);
      if (rank == null) return null;
      sum += rank;
    }
    return sum;
  }

  Future<String> _whyNoRunner(
    JobRecord job,
    List<String> kinds,
    Map<String, int> used,
    Set<String> signing,
    Future<List<PairedRunner>> Function() paired,
  ) async {
    final why = await _whyNot(job, kinds, signing, paired);
    final narrowing = job.narrowing;
    return narrowing.isEmpty
        ? why
        : '$why It needs ios-sign: ${narrowing.join('; ')}.';
  }

  Future<String> _whyNot(
    JobRecord job,
    List<String> kinds,
    Set<String> signing,
    Future<List<PairedRunner>> Function() paired,
  ) async {
    final needs = _needs(job);
    final wires = needs.map((need) => need.described).join(', ');
    final capable = _targets
        .where((runner) => _rank(needs, runner.capabilities) != null)
        .toList();
    if (capable.isEmpty) {
      final offline = [
        for (final runner in await paired())
          if (!runner.connected && _rank(needs, runner.capabilities) != null)
            _offline(runner, wires),
      ];
      if (offline.isEmpty) return 'No runner can do $wires.';
      return 'No connected runner can do $wires. ${offline.join(' ')}';
    }
    final accepting = capable.where((runner) => runner.accepts(kinds)).toList();
    if (accepting.isEmpty) {
      final engineOnly = {
        for (final kind in kinds)
          if (!capable.any((runner) => runner.accepts([kind]))) kind,
      }.toList()..sort();
      return 'Only the engine runs ${engineOnly.join(', ')}, and the engine '
          'cannot do $wires.';
    }
    if (_isIos(job) &&
        accepting.every((runner) => signing.contains(runner.id))) {
      final signs = needs.contains(const CapabilityNeed([Capability.iosSign]));
      return 'Waiting for the ${signs ? 'ios-sign' : 'iOS'} job that runs '
          'now: one at a time.';
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

  List<CapabilityNeed> _needs(JobRecord job) =>
      CapabilityNeed.parseAll(job.capabilities);

  /// Whether [job] takes the one iOS place of a machine.
  bool _isIos(JobRecord job) => _needs(job).any((need) => need.isIos);

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

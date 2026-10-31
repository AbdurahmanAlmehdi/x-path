import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/clock/clock.dart';
import 'package:xp_engine/src/jobs/job_exceptions.dart';
import 'package:xp_engine/src/jobs/job_logs.dart';
import 'package:xp_engine/src/jobs/job_record.dart';
import 'package:xp_engine/src/jobs/job_repository.dart';
import 'package:xp_engine/src/jobs/job_runner.dart';
import 'package:xp_engine/src/probe/runner_probe.dart';
import 'package:xp_engine/src/process/output_line.dart';
import 'package:xp_engine/src/process/output_masker.dart';
import 'package:xp_engine/src/projects/github_remote.dart';
import 'package:xp_engine/src/projects/project_repository.dart';
import 'package:xp_engine/src/repositories/event_log.dart';
import 'package:xp_engine/src/runners/remote_runner.dart';
import 'package:xp_engine/src/runners/remote_step_policy.dart';
import 'package:xp_engine/src/runners/runner_link.dart';
import 'package:xp_engine/src/runners/runner_record.dart';
import 'package:xp_engine/src/runners/runner_repository.dart';
import 'package:xp_engine/src/runners/runner_secret_grants.dart';
import 'package:xp_engine/src/runners/serial_queues.dart';
import 'package:xp_engine/src/scheduler/paired_runners.dart';
import 'package:xp_engine/src/scheduler/scheduler.dart';
import 'package:xp_engine/src/scheduler/scheduler_runner.dart';
import 'package:xp_engine/src/secrets/secret_store.dart';
import 'package:xp_engine/src/steps/build/dart_defines.dart';
import 'package:xp_engine/src/steps/git/git_checkout.dart';
import 'package:xp_engine/src/stores/apple/app_store_profiles.dart';

/// What the service that lists and revokes runners asks of the live part.
abstract interface class RunnerPresence {
  /// Where the runner [runnerId] is, as far as connections go: `online`,
  /// `draining` or `offline`.
  RunnerStatus statusOf(String runnerId);

  /// The jobs the runner [runnerId] holds a lease for.
  List<String> jobsOf(String runnerId);

  /// What the runner [runnerId] cannot do and why, from its last probe;
  /// `null` while it is not connected.
  List<MissingCapability>? missingOf(String runnerId);

  /// The runner was revoked: closes its connection and ends its leases.
  Future<void> revoked(RunnerRecord runner);
}

/// A lease: one job held by one runner until its heartbeats stop.
class _Lease {
  new({
    required this.id,
    required this.jobId,
    required this.runnerId,
    required this.projectId,
    required this.stepKinds,
    required this.grants,
    required this.defineFiles,
  });

  final String id;
  final String jobId;
  final String runnerId;
  final String projectId;

  /// The kinds of the steps, by ordinal.
  final List<String> stepKinds;

  /// The secret keys the runner may ask for, once each.
  final Set<String> grants;

  /// Those of [grants] that are define files, whose values are masked one by
  /// one.
  final Set<String> defineFiles;

  final delivered = <String>{};
  final stepLogs = <int, StepLog>{};
  final finished = Completer<void>();
  int nextChunk = 1;
  int lines = 0;
}

/// A connection of a runner.
class _Session {
  new(this.record, this.link, this.lastSeen);

  RunnerRecord record;
  final RunnerLink link;
  DateTime lastSeen;
  bool helloed = false;
  bool probed = false;
  bool closed = false;
  bool draining = false;
  String? probeId;
  DateTime? probeDeadline;
  DateTime? cooldownUntil;
  RemoteRunner? remote;
  List<MissingCapability> missing = const [];
}

/// The runners that are connected, the leases they hold and the rules that
/// make a lease the single source of truth about where a job runs (D-08).
///
/// A runner dials out (`GET /runners/connect`) and talks in frames
/// (`RunnerFrame`, `EngineFrame`):
///
/// - **Probe.** After `hello` the engine has the runner run its probe
///   commands and derives the capabilities from the results (D-19). The
///   runner gets jobs only after that, and the change of capabilities is
///   recorded as an event.
/// - **Lease.** The scheduler places a queued job on a [RemoteRunner]; the
///   hub marks the job `running` on the runner with a lease of 90 seconds and
///   sends a `lease_offer`. A heartbeat every 30 seconds renews the leases
///   the runner lists. A lease the runner does not renew is lost: the sweep
///   ends it. Every message about a job carries the id of the lease, so a
///   runner that comes back after its lease was lost cannot touch the job.
/// - **Loss rule.** A job that lost its lease is put back in the queue,
///   unless it has a step with side effects that is not done: then it is
///   `waiting_for_resume`, because a runner that was only unreachable may
///   still be doing it. Side effects are never repeated by themselves (D-08,
///   D-18).
/// - **Logs.** Output arrives in numbered chunks; the engine stores the next
///   one and answers the others with where it wants to go on, so duplicates
///   and gaps never reach the log.
/// - **Secrets.** A runner can ask for the signing material and the
///   Shorebird key the steps of its job name, once per lease (D-09, ADR 0012,
///   `RunnerSecretGrants`), and for a Linux iOS build the Apple Distribution
///   identity and the App Store profile the engine makes (ADR 0014,
///   `AppStoreProfiles`).
///
/// Every state change of a job is done under a per-job lock, so heartbeats,
/// reports, cancels and the sweep never interleave.
class RunnerHub
    implements RemoteLeases, RemoteJobs, RunnerPresence, PairedRunners {
  /// Creates the hub.
  ///
  /// [probeTimeout] is how long a runner has to answer the probe;
  /// [rejectCooldown] how long a runner that refused a job gets no more.
  /// [random] is for tests; it must be cryptographically secure otherwise.
  new({
    required this._runners,
    required this._projects,
    required this._jobs,
    required this._runner,
    required this._scheduler,
    required this._logs,
    required this._events,
    required this._clock,
    required this._secrets,
    required this._masker,
    required this._grants,
    required this._engineVersion,
    this.leaseLength = const Duration(seconds: runnerLeaseSeconds),
    this.probeTimeout = const Duration(seconds: 60),
    this.rejectCooldown = const Duration(seconds: 15),
    this.onError,
    this.onRefused,
    this._probe = const RunnerProbe(),
    this._profiles,
    Random? random,
  }) : _random = random ?? Random.secure();

  /// How long a lease lasts after the heartbeat that renewed it (D-08).
  /// Shorter only in tests.
  final Duration leaseLength;

  /// How often a runner sends a heartbeat: three times per lease, at least
  /// every second.
  Duration get heartbeatInterval =>
      Duration(seconds: max(1, leaseLength.inSeconds ~/ 3));

  /// How long a runner has to answer the probe.
  final Duration probeTimeout;

  /// How long a runner that refused a job gets no more.
  final Duration rejectCooldown;

  /// Hears about failures of the engine's own bookkeeping.
  final void Function(Object error, StackTrace stackTrace)? onError;

  /// Hears about a connection of the runner called `name` that the hub
  /// closed before the runner took part in scheduling (a protocol error, a
  /// probe that timed out), or that a newer connection replaced, and why.
  final void Function(String name, String why)? onRefused;

  final RunnerRepository _runners;
  final ProjectRepository _projects;
  final JobRepository _jobs;
  final JobRunner _runner;
  final Scheduler _scheduler;
  final JobLogs _logs;
  final EventLog _events;
  final Clock _clock;
  final SecretStore _secrets;
  final OutputMasker _masker;
  final RunnerSecretGrants _grants;
  final String _engineVersion;
  final RunnerProbe _probe;
  final AppStoreProfiles? _profiles;
  final Random _random;
  final _sessions = <String, _Session>{};
  final _leases = <String, _Lease>{};
  final _queues = SerialQueues();
  // The jobs the runners ended, so that a `job_done` that arrives twice is
  // answered twice. Bounded: the newest 512 stay.
  final _ended = <String, JobState>{};

  // ------------------------------------------------------------ connections

  /// Accepts the connection [link] of [runner] and sends the welcome.
  ///
  /// A connection of the same runner that is open is replaced (close code
  /// 4001); the leases the runner holds stay.
  RunnerConnection connect(RunnerRecord runner, RunnerLink link) {
    final session = _Session(runner, link, _clock.now());
    final previous = _sessions[runner.id];
    _sessions[runner.id] = session;
    if (previous != null) {
      _drop(previous, announce: false);
      onRefused?.call(
        runner.name,
        'replaced by a new connection of the same runner '
        '($runnerReplacedCloseCode)',
      );
      unawaited(
        previous.link
            .close(runnerReplacedCloseCode, 'replaced by a new connection')
            .catchError((Object _) {}),
      );
    }
    link.send(
      WelcomeFrame(
        runnerId: runner.id,
        engineVersion: _engineVersion,
        apiVersion: apiVersion,
        heartbeatSeconds: heartbeatInterval.inSeconds,
        leaseSeconds: leaseLength.inSeconds,
      ),
    );
    return RunnerConnection._(this, session);
  }

  /// Whether the runner [runnerId] has a connection open.
  bool isConnected(String runnerId) => _sessions.containsKey(runnerId);

  @override
  Future<List<PairedRunner>> pairedRunners() async => [
    for (final runner in await _runners.list())
      if (!runner.isRevoked)
        PairedRunner(
          id: runner.id,
          name: runner.name,
          capabilities: runner.capabilities,
          connected: isConnected(runner.id),
          lastSeen: runner.lastHeartbeat,
          missing: missingOf(runner.id) ?? const [],
        ),
  ];

  @override
  RunnerStatus statusOf(String runnerId) {
    final session = _sessions[runnerId];
    if (session == null || !session.probed) return RunnerStatus.offline;
    return session.draining ? RunnerStatus.draining : RunnerStatus.online;
  }

  @override
  List<String> jobsOf(String runnerId) => [
    for (final lease in _leases.values)
      if (lease.runnerId == runnerId) lease.jobId,
  ]..sort();

  @override
  List<MissingCapability>? missingOf(String runnerId) {
    final session = _sessions[runnerId];
    if (session == null || !session.probed) return null;
    return session.missing;
  }

  @override
  int slotsOf(String runnerId) {
    final session = _sessions[runnerId];
    if (session == null || !session.probed || session.draining) return 0;
    final cooldown = session.cooldownUntil;
    if (cooldown != null && _clock.now().isBefore(cooldown)) return 0;
    return session.record.slots;
  }

  /// Whether the runner [runnerId] holds the lease [leaseId] of [jobId] now.
  bool holdsLease(String runnerId, String jobId, String leaseId) {
    final lease = _leases[jobId];
    return lease != null && lease.id == leaseId && lease.runnerId == runnerId;
  }

  @override
  Future<void> revoked(RunnerRecord runner) async {
    final session = _sessions.remove(runner.id);
    if (session != null) {
      _drop(session, announce: true, reason: 'revoked');
      unawaited(
        session.link
            .close(runnerRevokedCloseCode, 'revoked')
            .catchError((Object _) {}),
      );
    }
    final held = await _jobs.list(states: {JobState.running});
    for (final job in held) {
      if (job.runnerId == runner.id) await _lose(job.id, 'revoked');
    }
  }

  // ----------------------------------------------------------------- leases

  @override
  Future<void> offer(String runnerId, String jobId) async {
    var offerFailed = false;
    await _locked(jobId, () async {
      final session = _sessions[runnerId];
      if (session == null || !session.probed || session.closed) {
        throw JobStateException('Runner $runnerId is not connected.');
      }
      final job = await _jobs.get(jobId) ?? (throw JobNotFoundException(jobId));
      if (job.state != JobState.queued) {
        throw JobStateException(
          'Job $jobId is ${job.state.wire}, not queued, so it cannot be '
          'leased.',
        );
      }
      final steps = await _jobs.steps(jobId);
      final engineOnly = RemoteStepPolicy.engineOnlyIn([
        for (final step in steps) step.kind,
      ]);
      if (engineOnly.isNotEmpty) {
        throw JobStateException(
          'Job $jobId has steps that only the engine runs '
          '(${engineOnly.join(', ')}), so it cannot go to a runner.',
        );
      }
      final now = _clock.now();
      final until = now.add(leaseLength);
      final grants = await _grants.forSteps(job.projectId, steps);
      final lease = _Lease(
        id: 'lse_${_hex(8)}',
        jobId: jobId,
        runnerId: runnerId,
        projectId: job.projectId,
        stepKinds: [for (final step in steps) step.kind],
        grants: grants,
        defineFiles: grants.intersection(
          RunnerSecretGrants.defineFilesOf(steps),
        ),
      );
      await _jobs.updateJob(
        job.copyWith(
          state: JobState.running,
          runnerId: runnerId,
          leaseUntil: until,
          message: null,
          startedAt: now,
          finishedAt: null,
        ),
      );
      _announce(job, JobState.running);
      await _logs.begin(jobId);
      _leases[jobId] = lease;
      try {
        session.link.send(
          LeaseOfferFrame(
            leaseId: lease.id,
            jobId: jobId,
            projectId: job.projectId,
            sha: await _commitOf(job, steps),
            name: job.name,
            repository: await _repositoryOf(job.projectId),
            stage: job.stage,
            capabilities: job.capabilities,
            expiresAt: until,
            steps: [
              for (final step in steps)
                LeaseStep(
                  ordinal: step.ordinal,
                  kind: step.kind,
                  sideEffect: step.sideEffect,
                  state: step.state,
                  attempts: step.attempts,
                  input: step.input,
                ),
            ],
            secrets: lease.grants.toList()..sort(),
          ),
        );
      } on Object {
        offerFailed = true;
      }
    });
    if (offerFailed) {
      // A connection that cannot take a frame is gone: without this the
      // scheduler would offer the job to it again, for ever.
      final broken = _sessions[runnerId];
      if (broken != null) {
        await _closeSession(
          broken,
          runnerTimeoutCloseCode,
          'the connection broke',
        );
      }
      await _lose(jobId, 'offer_failed');
    }
  }

  /// The exact commit the runner builds: the dispatched one, or the version
  /// commit of the earlier job that the `git.checkout` step starts from. A
  /// job that starts from a job which made no version commit gets no commit,
  /// and the runner fails it with that explanation instead of building the
  /// wrong source.
  Future<String?> _commitOf(JobRecord job, List<StepRecord> steps) async {
    final checkout = steps.where((s) => s.kind == 'git.checkout').firstOrNull;
    final source = checkout?.input['commitFromJob'];
    if (source is! String) return job.sha;
    return await versionCommitOf(_jobs, source);
  }

  /// Where the runner fetches the source of [projectId] from: the SSH URL of
  /// the repository and the key of its cache. Never a credential (ADR 0009).
  /// A remote that is not on GitHub (an SSH or `file://` one, ADR 0015) is
  /// sent as it is, without a password in the URL. The user of an `ssh://`
  /// URL stays: hosts such as Bitbucket only answer to `git`.
  Future<LeaseRepository?> _repositoryOf(String projectId) async {
    final project = await _projects.get(projectId);
    if (project == null) return null;
    final github = project.isOnGitHub
        ? GitHubRemote.parse(project.remote)
        : null;
    return LeaseRepository(
      cacheKey: project.sourceKey,
      sshUrl: github?.sshUrl ?? _withoutUserInfo(project.remote),
    );
  }

  static String _withoutUserInfo(String remote) {
    final uri = Uri.tryParse(remote);
    if (uri == null || !uri.hasScheme || uri.userInfo.isEmpty) return remote;
    if (uri.isScheme('ssh') && !uri.userInfo.contains(':')) return remote;
    return uri.replace(userInfo: '').toString();
  }

  @override
  Future<void> whenFinished(String jobId) =>
      _leases[jobId]?.finished.future ?? Future<void>.value();

  @override
  Future<bool> cancel(String id) => _locked(id, () async {
    final lease = _leases[id];
    final job = await _jobs.get(id);
    if (lease == null || job == null || job.state != JobState.running) {
      return false;
    }
    final now = _clock.now();
    for (final step in await _jobs.steps(id)) {
      if (step.state == StepState.running ||
          step.state == StepState.interrupted ||
          step.state == StepState.waitingForApproval) {
        await _saveStep(
          step.copyWith(
            state: StepState.cancelled,
            message: null,
            pgid: null,
            finishedAt: now,
          ),
        );
      }
    }
    await _jobs.updateJob(
      job.copyWith(
        state: JobState.cancelled,
        leaseUntil: null,
        message: 'Cancelled.',
        finishedAt: now,
      ),
    );
    _announce(job, JobState.cancelled);
    _tell(
      lease,
      CancelFrame(jobId: id, leaseId: lease.id, reason: 'Cancelled.'),
    );
    await _endLease(lease);
    return true;
  });

  /// Ends the leases that ran out, drops the connections that went quiet and
  /// asks the scheduler to place jobs again where a runner can take some
  /// again. The lease sweeper calls it every few seconds.
  Future<void> sweep() async {
    final now = _clock.now();
    var pump = false;
    for (final job in await _jobs.list(states: {JobState.running})) {
      final until = job.leaseUntil;
      if (job.runnerId == null || until == null || now.isBefore(until)) {
        continue;
      }
      await _lose(job.id, 'lapsed');
    }
    for (final session in _sessions.values.toList()) {
      final deadline = session.probeDeadline;
      final silent = now.difference(session.lastSeen) >= leaseLength;
      if (silent || (deadline != null && !now.isBefore(deadline))) {
        _sessions.remove(session.record.id);
        final why = silent
            ? 'no frame for ${leaseLength.inSeconds} s'
            : 'the probe timed out';
        _drop(
          session,
          announce: true,
          reason: why,
          code: runnerTimeoutCloseCode,
        );
        unawaited(
          session.link
              .close(
                runnerTimeoutCloseCode,
                silent ? 'no frame for a whole lease' : 'the probe timed out',
              )
              .catchError((Object _) {}),
        );
        continue;
      }
      final cooldown = session.cooldownUntil;
      if (cooldown != null && !now.isBefore(cooldown)) {
        session.cooldownUntil = null;
        pump = true;
      }
    }
    if (pump) await _scheduler.pump();
  }

  /// Loses the lease of [jobId] (D-08): see the class comment.
  Future<void> _lose(String jobId, String reason) =>
      _locked(jobId, () => _loseLocked(jobId, reason));

  /// [tell] sends the runner a cancel; a heartbeat that finds the lease lost
  /// answers the runner itself.
  Future<void> _loseLocked(
    String jobId,
    String reason, {
    bool tell = true,
  }) async {
    final lease = _leases[jobId];
    final job = await _jobs.get(jobId);
    final runnerId = job?.runnerId;
    if (job == null || job.state != JobState.running || runnerId == null) {
      if (lease != null) await _endLease(lease);
      return;
    }
    final now = _clock.now();
    final steps = await _jobs.steps(jobId);
    for (final step in steps) {
      if (step.state != StepState.running) continue;
      await _saveStep(
        step.copyWith(
          state: StepState.interrupted,
          message: 'The runner lost its lease while the step ran.',
          pgid: null,
          finishedAt: now,
        ),
      );
    }
    // A step with side effects that is not done may be under way on a runner
    // that is only out of reach, or may start once it is back: never repeat
    // it by itself.
    final sideEffects = steps.any((s) => s.sideEffect && !s.state.isDone);
    final state = sideEffects
        ? JobState.waitingForResume
        : JobState.interrupted;
    final name = (await _runners.get(runnerId))?.name ?? runnerId;
    await _jobs.updateJob(
      job.copyWith(
        state: state,
        runnerId: null,
        leaseUntil: null,
        message: sideEffects
            ? 'Runner $name lost its lease ($reason) while the job had a '
                  'step with side effects. Those are never repeated by '
                  'themselves: resume the job when you have checked.'
            : 'Runner $name lost its lease ($reason). The job runs again.',
        finishedAt: now,
      ),
    );
    _announce(job, state);
    _events.append(
      RunnerLeaseLost(
        runnerId: runnerId,
        jobId: jobId,
        projectId: job.projectId,
        reason: reason,
        state: sideEffects ? JobState.waitingForResume : JobState.queued,
      ),
    );
    if (lease != null) {
      if (tell) {
        _tell(
          lease,
          CancelFrame(
            jobId: jobId,
            leaseId: lease.id,
            reason: 'The lease was lost ($reason).',
          ),
        );
      }
      await _endLease(
        lease,
        beforeFinished: () async {
          if (!sideEffects) await _requeue(jobId);
        },
      );
    } else if (!sideEffects) {
      await _requeue(jobId);
    }
  }

  Future<void> _requeue(String jobId) async {
    try {
      await _runner.requeue(jobId);
    } on JobException {
      // Cancelled or resumed by someone else in the meantime.
    }
  }

  /// Closes the logs of the lease, forgets it, and lets those who wait for
  /// it go on. [beforeFinished] runs last before they do.
  Future<void> _endLease(
    _Lease lease, {
    Future<void> Function()? beforeFinished,
  }) async {
    _leases.remove(lease.jobId);
    try {
      for (final log in lease.stepLogs.values) {
        await log.close();
      }
      lease.stepLogs.clear();
      await _logs.end(lease.jobId);
      await beforeFinished?.call();
    } on Object catch (error, stackTrace) {
      onError?.call(error, stackTrace);
    } finally {
      if (!lease.finished.isCompleted) lease.finished.complete();
    }
  }

  // ----------------------------------------------------------------- frames

  Future<void> _onText(_Session session, String text) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      return await _protocolError(session, 'The frame is not JSON.');
    }
    if (decoded is! Map<String, dynamic>) {
      return await _protocolError(session, 'A frame is a JSON object.');
    }
    final RunnerFrame frame;
    try {
      frame = RunnerFrame.fromJson(decoded);
    } on FormatException catch (error) {
      return _fault(session, 'invalid_frame', error.message);
    }
    await _onFrame(session, frame);
  }

  Future<void> _protocolError(_Session session, String message) async {
    _fault(session, 'invalid_frame', message);
    await _closeSession(session, runnerProtocolCloseCode, message);
  }

  Future<void> _onFrame(_Session session, RunnerFrame frame) async {
    if (session.closed) return;
    session.lastSeen = _clock.now();
    if (!session.helloed) {
      if (frame is! HelloFrame) {
        _fault(session, 'unexpected_frame', 'The first frame is hello.');
        return await _closeSession(
          session,
          runnerProtocolCloseCode,
          'the first frame is hello',
        );
      }
      return await _hello(session, frame);
    }
    switch (frame) {
      case HelloFrame():
        _fault(session, 'unexpected_frame', 'hello was sent already.');
      case ProbeResultFrame():
        await _probed(session, frame);
      case LeaseAcceptFrame():
        await _accepted(session, frame);
      case LeaseRejectFrame():
        await _rejected(session, frame);
      case HeartbeatFrame():
        await _heartbeat(session, frame.leases, record: true);
      case LogChunkFrame():
        await _chunk(session, frame);
      case StepStateFrame():
        await _stepState(session, frame);
      case JobDoneFrame():
        await _done(session, frame);
      case SecretRequestFrame(:final key)
          when AppStoreProfiles.isProfileKey(key):
        // App Store Connect may take a while to make a profile: it is
        // answered aside, so the heartbeats behind it keep the lease.
        unawaited(
          _secretRequested(session, frame).catchError(onError ?? (Object _) {}),
        );
      case SecretRequestFrame():
        await _secretRequested(session, frame);
      case DrainFrame():
        await _drained(session, frame);
      case UnknownRunnerFrame(:final type):
        _fault(session, 'unknown_frame', 'This engine has no frame "$type".');
    }
  }

  Future<void> _onClosed(_Session session, int? code) async {
    session.closed = true;
    if (!identical(_sessions[session.record.id], session)) return;
    _sessions.remove(session.record.id);
    _drop(
      session,
      announce: true,
      reason: switch (code) {
        1000 || 1001 => 'the runner closed the connection',
        null || 1005 || 1006 => 'the connection dropped',
        final code => 'the runner closed the connection with code $code',
      },
    );
  }

  Future<void> _closeSession(_Session session, int code, String reason) async {
    if (identical(_sessions[session.record.id], session)) {
      _sessions.remove(session.record.id);
    }
    _drop(session, announce: true, reason: reason, code: code);
    try {
      await session.link.close(code, reason);
    } on Object {
      // Already closed.
    }
  }

  /// Takes the session out of the scheduler. Only a session that took part
  /// in scheduling was announced as connected, so only such a session is
  /// announced as disconnected, with the [reason], and not when another
  /// connection of the same runner replaced it ([announce] false). A session
  /// the hub closes with [code] before that is reported as refused.
  void _drop(
    _Session session, {
    required bool announce,
    String? reason,
    int? code,
  }) {
    session.closed = true;
    final remote = session.remote;
    if (remote == null) {
      if (code != null && announce) {
        onRefused?.call(session.record.name, '$reason ($code)');
      }
      return;
    }
    session.remote = null;
    _scheduler.removeRunner(session.record.id);
    if (announce) {
      _events.append(
        RunnerDisconnected(
          runnerId: session.record.id,
          name: session.record.name,
          reason: reason,
        ),
      );
    }
  }

  Future<void> _hello(_Session session, HelloFrame frame) async {
    session
      ..helloed = true
      ..draining = frame.draining;
    final now = _clock.now();
    final slots = max(1, frame.maxJobs ?? defaultSlots(frame.cores));
    await _save(
      session,
      (stored) => stored.copyWith(
        slots: slots,
        os: frame.os,
        arch: frame.arch,
        version: frame.version,
        cores: frame.cores,
        lastHeartbeat: now,
      ),
    );
    await _heartbeat(session, frame.leases, record: false, answer: false);
    final probeId = 'prb_${_hex(6)}';
    session
      ..probeId = probeId
      ..probeDeadline = now.add(probeTimeout);
    _send(session, ProbeFrame(probeId: probeId, commands: _probe.commands));
  }

  Future<void> _probed(_Session session, ProbeResultFrame frame) async {
    if (frame.probeId != session.probeId) return;
    session
      ..probeId = null
      ..probeDeadline = null;
    final before = session.record.capabilities;
    final findings = _probe.evaluate(
      frame.results,
      iosLinuxDirectory: frame.iosLinuxDir,
    );
    final found = findings.capabilities;
    await _save(session, (stored) => stored.copyWith(capabilities: found));
    final record = session.record;
    session.missing = findings.missing;
    _send(
      session,
      ProbedFrame(
        capabilities: RunnerRecord.wireNames(found),
        missing: findings.missing,
      ),
    );
    if (!(before.length == found.length && before.containsAll(found))) {
      _events.append(
        RunnerCapabilitiesChanged(
          runnerId: record.id,
          name: record.name,
          from: RunnerRecord.wireNames(before),
          to: RunnerRecord.wireNames(found),
        ),
      );
    }
    session.probed = true;
    final remote = RemoteRunner(
      id: record.id,
      capabilities: found,
      leases: this,
    );
    session.remote = remote;
    _scheduler
      ..removeRunner(record.id)
      ..addRunner(remote);
    _events.append(
      RunnerConnected(
        runnerId: record.id,
        name: record.name,
        capabilities: RunnerRecord.wireNames(found),
        slots: record.slots,
      ),
    );
    await _scheduler.pump();
  }

  Future<void> _accepted(_Session session, LeaseAcceptFrame frame) async {
    if (!_holds(session, frame.jobId, frame.leaseId)) {
      return _cancelUnknown(session, frame.jobId, frame.leaseId);
    }
    // The lease is renewed by heartbeats; the accept only proves the runner
    // took the job. One that comes after the lease ran out finds it lost.
    final until = await _locked(frame.jobId, () async {
      final lease = _leases[frame.jobId];
      if (lease == null || lease.id != frame.leaseId) return null;
      return await _renew(lease, _clock.now());
    });
    if (until == null) {
      _send(
        session,
        CancelFrame(
          jobId: frame.jobId,
          leaseId: frame.leaseId,
          reason: 'The lease ran out.',
        ),
      );
    }
  }

  Future<void> _rejected(_Session session, LeaseRejectFrame frame) async {
    if (!_holds(session, frame.jobId, frame.leaseId)) {
      return _cancelUnknown(session, frame.jobId, frame.leaseId);
    }
    if (frame.reason == 'draining') {
      session.draining = true;
    } else {
      session.cooldownUntil = _clock.now().add(rejectCooldown);
    }
    await _locked(frame.jobId, () async {
      final lease = _leases[frame.jobId];
      final job = await _jobs.get(frame.jobId);
      if (lease == null || lease.id != frame.leaseId) return;
      if (job != null && job.state == JobState.running) {
        await _jobs.updateJob(
          job.copyWith(
            state: JobState.queued,
            runnerId: null,
            leaseUntil: null,
            message: null,
            startedAt: null,
            finishedAt: null,
          ),
        );
        _announce(job, JobState.queued);
      }
      await _endLease(lease);
    });
  }

  /// Renews the leases in [refs] and answers with the ones that hold. Those
  /// the runner lists and the engine does not hold are cancelled.
  Future<void> _heartbeat(
    _Session session,
    List<LeaseRef> refs, {
    required bool record,
    bool answer = true,
  }) async {
    final now = _clock.now();
    if (record) {
      await _save(session, (stored) => stored.copyWith(lastHeartbeat: now));
    }
    final granted = <LeaseGrant>[];
    for (final ref in refs) {
      if (!_holds(session, ref.jobId, ref.leaseId)) {
        _cancelUnknown(session, ref.jobId, ref.leaseId);
        continue;
      }
      final until = await _locked(ref.jobId, () async {
        final lease = _leases[ref.jobId];
        if (lease == null || lease.id != ref.leaseId) return null;
        return await _renew(lease, now);
      });
      if (until == null) {
        _send(
          session,
          CancelFrame(
            jobId: ref.jobId,
            leaseId: ref.leaseId,
            reason: 'The lease ran out.',
          ),
        );
        continue;
      }
      granted.add(
        LeaseGrant(jobId: ref.jobId, leaseId: ref.leaseId, until: until),
      );
    }
    if (answer || granted.isNotEmpty) {
      _send(session, HeartbeatAckFrame(leases: granted));
    }
  }

  /// Extends [lease] to 90 seconds from [now]. A lease that ran out already
  /// is lost instead. Returns when it holds until, or `null`.
  Future<DateTime?> _renew(_Lease lease, DateTime now) async {
    final job = await _jobs.get(lease.jobId);
    final until = job?.leaseUntil;
    if (job == null || until == null || !now.isBefore(until)) {
      await _loseLocked(lease.jobId, 'lapsed', tell: false);
      return null;
    }
    final renewed = now.add(leaseLength);
    final held = await _jobs.renewLease(
      lease.jobId,
      runnerId: lease.runnerId,
      until: renewed,
    );
    if (!held) {
      await _endLease(lease);
      return null;
    }
    return renewed;
  }

  Future<void> _chunk(_Session session, LogChunkFrame frame) async {
    if (!_holds(session, frame.jobId, frame.leaseId)) {
      return _cancelUnknown(session, frame.jobId, frame.leaseId);
    }
    if (frame.lines.length > LogChunkFrame.maxLines) {
      return _fault(
        session,
        'chunk_too_large',
        'A chunk has at most ${LogChunkFrame.maxLines} lines.',
      );
    }
    await _locked(frame.jobId, () async {
      final lease = _leases[frame.jobId];
      if (lease == null || lease.id != frame.leaseId) return;
      final ChunkStatus status;
      if (frame.seq < lease.nextChunk) {
        status = ChunkStatus.duplicate;
      } else if (frame.seq > lease.nextChunk) {
        status = ChunkStatus.gap;
      } else {
        await _store(lease, frame.lines);
        lease.nextChunk++;
        status = ChunkStatus.stored;
      }
      _send(
        session,
        ChunkAckFrame(
          jobId: lease.jobId,
          leaseId: lease.id,
          seq: frame.seq,
          next: lease.nextChunk,
          status: status,
        ),
      );
    });
  }

  /// Masks the lines once more, numbers them in the log of the job and
  /// shows them to those who follow it. Lines of a step the job does not have
  /// are dropped.
  Future<void> _store(_Lease lease, List<ChunkLine> lines) async {
    for (final line in lines) {
      if (line.step < 0 || line.step >= lease.stepKinds.length) continue;
      final log = lease.stepLogs[line.step] ??= await _openLog(
        lease,
        line.step,
      );
      await log.record(
        OutputLine(
          seq: ++lease.lines,
          timestamp: line.at,
          stream: line.stream,
          text: _mask(line.text),
        ),
      );
    }
  }

  Future<StepLog> _openLog(_Lease lease, int ordinal) async {
    final log = await _logs.openStep(
      lease.jobId,
      ordinal,
      lease.stepKinds[ordinal],
    );
    final steps = await _jobs.steps(lease.jobId);
    await _jobs.updateStep(steps[ordinal].copyWith(logPath: log.path));
    return log;
  }

  Future<void> _stepState(_Session session, StepStateFrame frame) async {
    if (!_holds(session, frame.jobId, frame.leaseId)) {
      return _cancelUnknown(session, frame.jobId, frame.leaseId);
    }
    await _locked(frame.jobId, () async {
      final lease = _leases[frame.jobId];
      if (lease == null || lease.id != frame.leaseId) return;
      final steps = await _jobs.steps(frame.jobId);
      if (frame.ordinal < 0 || frame.ordinal >= steps.length) {
        return _fault(
          session,
          'invalid_frame',
          'Job ${frame.jobId} has no step ${frame.ordinal}.',
        );
      }
      final step = steps[frame.ordinal];
      final newer =
          frame.attempts > step.attempts ||
          (frame.attempts == step.attempts &&
              _rank(frame.state) > _rank(step.state));
      if (!newer) return;
      final now = _clock.now();
      await _saveStep(
        step.copyWith(
          state: frame.state,
          attempts: frame.attempts,
          result: frame.result,
          message: frame.message == null ? null : _mask(frame.message!),
          pgid: null,
          startedAt: frame.startedAt ?? step.startedAt ?? now,
          finishedAt:
              frame.finishedAt ?? (_rank(frame.state) == 2 ? now : null),
        ),
      );
    });
  }

  static int _rank(StepState state) => switch (state) {
    StepState.pending => 0,
    StepState.running => 1,
    _ => 2,
  };

  Future<void> _done(_Session session, JobDoneFrame frame) async {
    final recorded = _ended['${frame.jobId}/${frame.leaseId}'];
    if (recorded != null) {
      // A report that arrived twice: the engine recorded it already.
      return _send(
        session,
        DoneAckFrame(
          jobId: frame.jobId,
          leaseId: frame.leaseId,
          state: recorded,
        ),
      );
    }
    if (!_holds(session, frame.jobId, frame.leaseId)) {
      return _cancelUnknown(session, frame.jobId, frame.leaseId);
    }
    await _locked(frame.jobId, () async {
      final lease = _leases[frame.jobId];
      final job = await _jobs.get(frame.jobId);
      if (lease == null || lease.id != frame.leaseId || job == null) return;
      if (frame.lastChunk >= lease.nextChunk) {
        // The log is not complete: the runner sends what is missing first.
        return _send(
          session,
          ChunkAckFrame(
            jobId: lease.jobId,
            leaseId: lease.id,
            seq: frame.lastChunk,
            next: lease.nextChunk,
            status: ChunkStatus.gap,
          ),
        );
      }
      final now = _clock.now();
      final steps = await _jobs.steps(frame.jobId);
      final unfinished = steps.where((s) => !s.state.isDone).firstOrNull;
      var state = frame.state;
      var message = frame.message == null ? null : _mask(frame.message!);
      if (state == JobState.succeeded && unfinished != null) {
        state = JobState.failed;
        message =
            'The runner reported the job done, but step ${unfinished.ordinal} '
            '(${unfinished.kind}) is ${unfinished.state.name}.';
      }
      if (state == JobState.failed && message == null) {
        final failed = steps
            .where((s) => s.state == StepState.failed)
            .firstOrNull;
        message = failed == null
            ? 'The runner reported the job failed.'
            : 'Step ${failed.ordinal} (${failed.kind}) failed: '
                  '${failed.message}';
      }
      for (final step in steps) {
        if (step.state != StepState.running) continue;
        await _saveStep(
          step.copyWith(
            state: state == JobState.cancelled
                ? StepState.cancelled
                : StepState.failed,
            message: state == JobState.cancelled
                ? null
                : 'The job ended without a report of this step.',
            pgid: null,
            finishedAt: now,
          ),
        );
      }
      await _jobs.updateJob(
        job.copyWith(
          state: state,
          leaseUntil: null,
          message: state == JobState.succeeded ? null : message,
          finishedAt: now,
        ),
      );
      _announce(job, state);
      _ended['${lease.jobId}/${lease.id}'] = state;
      if (_ended.length > 512) _ended.remove(_ended.keys.first);
      await _endLease(lease);
      _send(
        session,
        DoneAckFrame(jobId: lease.jobId, leaseId: lease.id, state: state),
      );
    });
  }

  Future<void> _secretRequested(
    _Session session,
    SecretRequestFrame frame,
  ) async {
    if (!_holds(session, frame.jobId, frame.leaseId)) {
      return _cancelUnknown(session, frame.jobId, frame.leaseId);
    }
    final lease = _leases[frame.jobId]!;
    void deny(String reason) => _send(
      session,
      SecretDeniedFrame(
        jobId: frame.jobId,
        leaseId: frame.leaseId,
        key: frame.key,
        reason: reason,
      ),
    );
    if (!lease.grants.contains(frame.key)) {
      return deny(
        'This is not signing material, a Shorebird key or a define file that '
        'the job names.',
      );
    }
    if (!lease.delivered.add(frame.key)) {
      return deny('It was given for this lease already.');
    }
    final List<int>? bytes;
    try {
      bytes = AppStoreProfiles.isProfileKey(frame.key)
          ? await _profiles?.profile(lease.projectId, frame.key)
          : await _secrets.readBytes(frame.key);
    } on SecretStoreException {
      lease.delivered.remove(frame.key);
      return deny('The engine cannot read its secrets right now.');
    } on AppStoreProfileException catch (error) {
      lease.delivered.remove(frame.key);
      return deny(error.message);
    }
    if (bytes == null) return deny('There is no such secret.');
    // A profile is made while other frames are handled: the lease may be gone.
    if (!_holds(session, frame.jobId, frame.leaseId)) return;
    // The runner masks what it holds; the engine masks what comes back too.
    try {
      final text = utf8.decode(bytes);
      if (lease.defineFiles.contains(frame.key)) {
        dartDefineSecrets(text).forEach(_masker.add);
      } else if (text.isNotEmpty) {
        _masker.add(text);
      }
    } on FormatException {
      // Binary material, a keystore: nothing readable to mask.
    }
    _send(
      session,
      SecretValueFrame(
        jobId: frame.jobId,
        leaseId: frame.leaseId,
        key: frame.key,
        value: base64Encode(bytes),
      ),
    );
    _events.append(
      RunnerSecretDelivered(
        runnerId: session.record.id,
        jobId: frame.jobId,
        key: frame.key,
      ),
    );
  }

  Future<void> _drained(_Session session, DrainFrame frame) async {
    final wasDraining = session.draining;
    session.draining = frame.draining;
    if (wasDraining && !frame.draining) await _scheduler.pump();
  }

  // ---------------------------------------------------------------- helpers

  /// Saves what [change] makes of the runner as it is stored now, so that a
  /// revoke that happened meanwhile is not written over.
  Future<void> _save(
    _Session session,
    RunnerRecord Function(RunnerRecord stored) change,
  ) async {
    final stored =
        await _runners.get(session.record.id) ??
        (throw StateError('There is no runner ${session.record.id}.'));
    session.record = change(stored);
    await _runners.update(session.record);
  }

  bool _holds(_Session session, String jobId, String leaseId) =>
      holdsLease(session.record.id, jobId, leaseId);

  void _cancelUnknown(_Session session, String jobId, String leaseId) => _send(
    session,
    CancelFrame(
      jobId: jobId,
      leaseId: leaseId,
      reason: 'The engine holds no such lease.',
    ),
  );

  void _fault(_Session session, String code, String message) =>
      _send(session, FaultFrame(code: code, message: message));

  void _send(_Session session, EngineFrame frame) {
    try {
      session.link.send(frame);
    } on Object {
      // The connection broke; the runner's leases run out by themselves.
    }
  }

  void _tell(_Lease lease, EngineFrame frame) {
    final session = _sessions[lease.runnerId];
    if (session != null) _send(session, frame);
  }

  Future<void> _saveStep(StepRecord step) async {
    await _jobs.updateStep(step);
    _events.append(
      JobStepChanged(
        jobId: step.jobId,
        ordinal: step.ordinal,
        kind: step.kind,
        state: step.state,
      ),
    );
  }

  void _announce(JobRecord job, JobState state) => _events.append(
    JobStateChanged(jobId: job.id, projectId: job.projectId, state: state),
  );

  Future<T> _locked<T>(String jobId, Future<T> Function() action) =>
      _queues.run(jobId, action);

  String _mask(String text) {
    final stream = _masker.newStream();
    return stream.add(text) + stream.flush();
  }

  String _hex(int bytes) => List.generate(
    bytes,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

/// One connection of a runner, as the WebSocket route holds it.
///
/// The route passes every text frame to [receiveText] and calls [closed]
/// when the socket ends. Frames of one connection are handled one after the
/// other, in the order they arrived.
class RunnerConnection {
  new _(this._hub, this._session);

  final RunnerHub _hub;
  final _Session _session;
  Future<void> _tail = Future<void>.value();

  /// The runner this connection is for.
  String get runnerId => _session.record.id;

  /// Handles the text frame [text].
  Future<void> receiveText(String text) =>
      _enqueue(() => _hub._onText(_session, text));

  /// Handles the frame [frame].
  Future<void> receive(RunnerFrame frame) =>
      _enqueue(() => _hub._onFrame(_session, frame));

  /// The socket ended, with the close [code] the runner sent, if any.
  Future<void> closed([int? code]) =>
      _enqueue(() => _hub._onClosed(_session, code));

  Future<void> _enqueue(Future<void> Function() handle) {
    final next = _tail.then((_) async {
      try {
        await handle();
      } on Object catch (error, stackTrace) {
        _hub.onError?.call(error, stackTrace);
      }
    });
    _tail = next;
    return next;
  }
}

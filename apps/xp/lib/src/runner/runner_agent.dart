import 'dart:async';
import 'dart:convert';

import 'package:xp/src/runner/backoff.dart';
import 'package:xp/src/runner/job/lease_outbox.dart';
import 'package:xp/src/runner/job/leased_job.dart';
import 'package:xp/src/runner/runner_socket.dart';
import 'package:xp/src/runner/secrets/lease_secret_store.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_engine/xp_engine.dart' show ProbeExecutor;

/// Why [RunnerAgent.run] ended.
enum AgentExit {
  /// The runner was told to drain and finished its jobs.
  drained,

  /// A `--one-shot` runner ran its one job.
  oneShotDone,

  /// The engine closed the connection because the runner was revoked.
  revoked,

  /// Another connection of the same runner replaced this one.
  replaced,

  /// The engine does not accept the credential.
  credentialRejected,

  /// The runner was stopped: its jobs were cancelled and nothing was reported.
  stopped,

  /// The engine runs another version than the runner, and the runner finished
  /// its jobs and took no new one: it is time to update (D-24). See
  /// [RunnerAgent.updateVersion].
  updateRequired,

  /// The runner switched to another version (an update or a rollback) and has
  /// to start again as it. Never returned by the agent itself.
  updated,
}

/// Starts the job of a lease that was accepted. `requestSecret` asks the
/// engine for a secret of the lease.
typedef LeaseStarter = LeaseWork Function(
  LeaseOfferFrame offer,
  LeaseOutbox outbox,
  SecretRequester requestSecret,
);

class _Lease {
  const new(this.offer, this.outbox, this.work);

  final LeaseOfferFrame offer;
  final LeaseOutbox outbox;
  final LeaseWork work;

  LeaseRef get ref => LeaseRef(jobId: offer.jobId, leaseId: offer.leaseId);
  bool get needsIosSign => offer.capabilities.contains('ios-sign');
}

/// The runner: dials out to the engine and does what it says (D-08, D-19).
///
/// - **Connects** with the credential, and again, with an exponential backoff
///   and jitter, whenever the connection drops. Nothing ever connects to a
///   runner.
/// - **Says hello** (version, system, cores, the most jobs it will run, the
///   leases it still holds), **runs the probe** the engine sends, and gets
///   jobs only after that. It never claims capabilities; the engine derives
///   them from the probe and says what it found (`probed`), which the runner
///   prints the first time and whenever it changes: what it offers and, for
///   each capability it lacks, why and what gives it.
/// - **Takes leases** within its slots (an `ios-sign` job never runs beside
///   another), refuses the others with a reason, and refuses all of them
///   while draining. **Heartbeats** every `heartbeatSeconds` of the welcome,
///   well inside the lease of 90 seconds.
/// - **Reports** through each lease's [LeaseOutbox], which keeps what the
///   engine has not acknowledged and sends it again after a reconnect.
/// - **Obeys `cancel`**: the job's process groups end, its secrets and files
///   are wiped, nothing more is reported.
/// - **Fences a lost lease** (D-08): a lease the engine has not renewed for
///   its whole length plus 15 seconds (one sweep and some clock skew) is one
///   the engine has given up, so the runner stops the job as a `cancel` would
///   and drops what its outbox still held. It measures with a monotonic clock
///   from the last acknowledgement, so the clocks of the engine and the
///   runner need not agree.
/// - **Stays quiet while the engine is away**: one line when the connection
///   is lost, one for the first failed attempt, then at most one every
///   [nagInterval], and one when it is back.
/// - **Drains** (finish the jobs, take none, exit) and, with `oneShot`, takes
///   one job and exits after it.
/// - **Updates between jobs** (D-24): when the version in the engine's
///   `welcome` is one the runner should update to (`wantsUpdateTo`), it says
///   `draining` in its hello, refuses every offer ("updating"), lets the jobs
///   it holds finish and then ends with [AgentExit.updateRequired]. It never
///   ends a job to update. Whoever runs the agent updates and starts it again.
class RunnerAgent {
  /// Creates the agent.
  new({
    required this._connect,
    required this._start,
    required this._probe,
    required this._stepKinds,
    required this._log,
    required this.version,
    required this.os,
    required this.arch,
    required this.cores,
    required this.slots,
    this.requestedSlots,
    this.oneShot = false,
    this.secretTimeout = const Duration(seconds: 60),
    Backoff? backoff,
    Future<void> Function(Duration)? delay,
    Duration Function(int seconds)? heartbeatUnit,
    this.wantsUpdateTo,
    this.onWelcomed,
    this.fenceInterval = const Duration(seconds: 5),
    this.fenceGrace = const Duration(seconds: 15),
    this.nagInterval = const Duration(minutes: 10),
    Duration Function()? elapsed,
  }) : _backoff = backoff ?? Backoff(),
       _delay = delay ?? Future<void>.delayed,
       _heartbeatUnit =
           heartbeatUnit ?? ((seconds) => Duration(seconds: seconds)),
       _elapsed = elapsed ?? _monotonic();

  final RunnerConnector _connect;
  final LeaseStarter _start;
  final ProbeExecutor _probe;
  final Set<String> _stepKinds;
  final void Function(String message) _log;
  final Backoff _backoff;
  final Future<void> Function(Duration) _delay;
  final Duration Function(int seconds) _heartbeatUnit;

  /// A monotonic clock: the time since the agent was made.
  final Duration Function() _elapsed;

  /// The `xp` version sent in the hello.
  final String version;

  /// The operating system sent in the hello.
  final String os;

  /// The processor architecture sent in the hello.
  final String arch;

  /// The processor cores sent in the hello.
  final int cores;

  /// How many jobs the runner takes at once.
  final int slots;

  /// The `--slots` the owner gave, sent as `maxJobs`; `null` leaves the
  /// default to the engine.
  final int? requestedSlots;

  /// Whether the runner exits after its first job.
  final bool oneShot;

  /// How long a request for a secret waits for the engine.
  final Duration secretTimeout;

  /// Whether the runner should update to the engine version it is told in the
  /// `welcome`. `null` never updates (a one-shot runner, a runner that cannot
  /// update).
  final bool Function(String engineVersion)? wantsUpdateTo;

  /// Called with the engine version at every welcome: the engine accepted the
  /// runner, which is what proves a new version works.
  final void Function(String engineVersion)? onWelcomed;

  /// How often the leases are checked against their length.
  final Duration fenceInterval;

  /// How long past its length a lease is kept before it counts as lost.
  final Duration fenceGrace;

  /// The least time between two lines that say the engine is still away.
  final Duration nagInterval;

  final _active = <String, _Lease>{};
  final _secrets = <String, Completer<List<int>?>>{};
  final _askedSecrets = <String, SecretRequestFrame>{};
  RunnerSocket? _socket;
  Timer? _heartbeat;
  AgentExit? _exit;
  var _draining = false;
  String? _updateTo;
  String? _engineVersion;
  ProbedFrame? _offers;
  var _leaseLength = const Duration(seconds: runnerLeaseSeconds);
  // When the engine last renewed each lease, on the monotonic clock.
  final _renewed = <String, Duration>{};
  Timer? _fence;
  // Since when the engine is away, and when the runner last said so.
  Duration? _awaySince;
  Duration? _saidAwayAt;
  var _tookJob = false;
  Completer<void>? _wake;

  /// How many jobs run now (including the ones whose end the engine has not
  /// acknowledged yet).
  int get activeJobs => _active.length;

  /// Whether the runner takes no more jobs.
  bool get isDraining => _draining;

  /// The engine version the runner has to update to, once [run] ended with
  /// [AgentExit.updateRequired]; also while it waits for its jobs to finish.
  String? get updateVersion => _updateTo;

  // ------------------------------------------------------------- the loop

  /// Connects, serves and reconnects until the runner has to end.
  Future<AgentExit> run() async {
    _fence = Timer.periodic(fenceInterval, (_) => unawaited(_fenceLost()));
    while (_exit == null) {
      final RunnerSocket socket;
      try {
        socket = await _connect();
      } on ApiException catch (error) {
        if (error.isUnauthorized || error.isForbidden) {
          _log(
            'The engine does not accept this runner: ${error.message} Pair it '
            'again: xp runner pair --engine <url> --token <pairing token>',
          );
          _exit = AgentExit.credentialRejected;
          break;
        }
        _cannotConnect(error.message);
        await _backOff();
        continue;
      } on Object catch (error) {
        _cannotConnect(_describe(error));
        await _backOff();
        continue;
      }
      final broke = await _serve(socket);
      if (_exit != null) break;
      switch (socket.closeCode) {
        case runnerRevokedCloseCode:
          _log('The engine revoked this runner. It does not connect again.');
          _exit = AgentExit.revoked;
        case runnerReplacedCloseCode:
          _log(
            'Another connection of this runner took over. Is it running '
            'twice? This one stops.',
          );
          _exit = AgentExit.replaced;
        default:
          _log(
            broke == null
                ? 'The connection to the engine ended; connecting again.'
                : 'The connection to the engine broke ($broke); connecting '
                      'again.',
          );
          _awaySince ??= _elapsed();
          _saidAwayAt = _elapsed();
          await _backOff();
      }
    }
    await _stopWork();
    return _exit!;
  }

  /// Says that an attempt failed: the first one, then at most once every
  /// [nagInterval].
  void _cannotConnect(String why) {
    final now = _elapsed();
    final since = _awaySince;
    if (since == null) {
      _awaySince = now;
      _saidAwayAt = now;
      _log('Cannot connect: $why');
      return;
    }
    final said = _saidAwayAt;
    if (said != null && now - said < nagInterval) return;
    _saidAwayAt = now;
    _log(
      'The engine has been unreachable for ${_span(now - since)}; still '
      'trying every ${_backoff.max.inSeconds} s. Last: $why',
    );
  }

  /// Stops the jobs whose lease the engine must have given up: not renewed
  /// for its whole length and [fenceGrace].
  Future<void> _fenceLost() async {
    final now = _elapsed();
    for (final lease in _active.values.toList()) {
      final renewed = _renewed[lease.offer.jobId];
      if (renewed == null || now - renewed <= _leaseLength + fenceGrace) {
        continue;
      }
      await _end(
        lease,
        'Lost the lease of job ${lease.offer.jobId} while the engine was '
        'unreachable; stopped it.',
      );
    }
  }

  static Duration Function() _monotonic() {
    final watch = Stopwatch()..start();
    return () => watch.elapsed;
  }

  static String _span(Duration duration) {
    if (duration < const Duration(minutes: 1)) {
      return '${duration.inSeconds} s';
    }
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    if (hours == 0) return '$minutes min';
    return minutes == 0 ? '$hours h' : '$hours h $minutes min';
  }

  Future<void> _backOff() {
    if (_exit != null) return Future<void>.value();
    final wait = _wait();
    return Future.any([_delay(_backoff.next()), wait]);
  }

  /// Completes when something asks the loop to look at its exit conditions.
  Future<void> _wait() => (_wake ??= Completer<void>()).future;

  void _wakeUp() {
    final wake = _wake;
    _wake = null;
    if (wake != null && !wake.isCompleted) wake.complete();
  }

  /// Asks the runner to drain: no more jobs, finish the ones it holds, exit.
  void drain() {
    if (_draining) return;
    _draining = true;
    _log('Draining: no new jobs; the running ones finish first.');
    _sendFrame(const DrainFrame());
    _checkExit();
  }

  /// Stops the runner now: its jobs are cancelled and nothing is reported. The
  /// engine ends their leases when they run out (D-08).
  Future<void> stop() async {
    _exit ??= AgentExit.stopped;
    await _closeSocket();
    _wakeUp();
  }

  void _checkExit() {
    if (_exit != null || _active.isNotEmpty) return;
    if (oneShot && _tookJob) {
      _exit = AgentExit.oneShotDone;
    } else if (_draining) {
      _exit = AgentExit.drained;
    } else if (_updateTo != null) {
      _exit = AgentExit.updateRequired;
    } else {
      return;
    }
    unawaited(_closeSocket());
    _wakeUp();
  }

  Future<void> _closeSocket() async {
    final socket = _socket;
    if (socket == null) return;
    try {
      await socket.close(1000, 'runner is done');
    } on Object {
      // Already closed.
    }
  }

  Future<void> _stopWork() async {
    _fence?.cancel();
    _heartbeat?.cancel();
    final leases = _active.values.toList();
    _active.clear();
    await Future.wait<void>([for (final lease in leases) lease.work.cancel()]);
    for (final completer in _secrets.values) {
      if (!completer.isCompleted) completer.complete(null);
    }
    _secrets.clear();
    _askedSecrets.clear();
  }

  // ------------------------------------------------------------ one connection

  /// Serves [socket] until it closes; returns why it broke, if it did.
  Future<String?> _serve(RunnerSocket socket) async {
    _socket = socket;
    try {
      // The runner was told to end while it was connecting: there is no need
      // to wait for a frame of the engine to notice.
      if (_exit != null) {
        unawaited(_closeSocket());
        return null;
      }
      await for (final text in socket.frames) {
        try {
          await _onText(text);
        } on Object catch (error) {
          _log('A frame of the engine could not be handled: $error');
        }
        if (_exit != null) break;
      }
    } on Object catch (error) {
      return _describe(error);
    } finally {
      _heartbeat?.cancel();
      _heartbeat = null;
      _socket = null;
    }
    return null;
  }

  Future<void> _onText(String text) async {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      _log('The engine sent something that is not JSON.');
      return;
    }
    if (decoded is! Map<String, dynamic>) return;
    final EngineFrame frame;
    try {
      frame = EngineFrame.fromJson(decoded);
    } on FormatException catch (error) {
      _log('The engine sent a frame this runner cannot read: ${error.message}');
      return;
    }
    switch (frame) {
      case WelcomeFrame():
        _welcome(frame);
      case ProbeFrame():
        await _probed(frame);
      case ProbedFrame():
        _found(frame);
      case LeaseOfferFrame():
        _offered(frame);
      case HeartbeatAckFrame():
        _acknowledged(frame);
      case ChunkAckFrame():
        _active[frame.jobId]?.outbox.chunkAcknowledged(frame);
      case DoneAckFrame():
        _ended(frame);
      case CancelFrame():
        await _cancelled(frame);
      case SecretValueFrame():
        _secretValue(frame);
      case SecretDeniedFrame():
        _secretDenied(frame);
      case FaultFrame():
        _log(
          'The engine could not use a frame (${frame.code}): ${frame.message}',
        );
      case UnknownEngineFrame():
        // A newer engine may send what this runner does not know.
        break;
    }
  }

  void _welcome(WelcomeFrame frame) {
    _backoff.reset();
    _engineVersion = frame.engineVersion;
    _leaseLength = Duration(seconds: frame.leaseSeconds);
    if (_awaySince case final since?) {
      _log('Connected again after ${_span(_elapsed() - since)}.');
      _awaySince = null;
      _saidAwayAt = null;
    }
    _decideUpdate(frame.engineVersion);
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(
      _heartbeatUnit(frame.heartbeatSeconds),
      (_) => _sendHeartbeat(),
    );
    _sendFrame(
      HelloFrame(
        version: version,
        os: os,
        arch: arch,
        cores: cores,
        maxJobs: requestedSlots,
        draining: _draining || _updateTo != null,
        leases: [for (final lease in _active.values) lease.ref],
      ),
    );
    // What the engine may not have of the jobs that ran across the drop.
    for (final lease in _active.values) {
      lease.outbox.resend();
    }
    _askedSecrets.values.forEach(_sendFrame);
    onWelcomed?.call(frame.engineVersion);
    // No job runs: the update starts at once.
    _checkExit();
  }

  /// Decides at a welcome whether to update, and says so once.
  void _decideUpdate(String engineVersion) {
    final wants = wantsUpdateTo?.call(engineVersion) ?? false;
    final before = _updateTo;
    _updateTo = wants ? engineVersion : null;
    if (wants && before != engineVersion) {
      final running = _active.length;
      final then = switch (running) {
        0 => 'the runner updates now',
        1 => 'the running job finishes, then the runner updates',
        _ => 'the $running running jobs finish, then the runner updates',
      };
      _log(
        'The engine runs $engineVersion; this runner ($version) updates to '
        'it between jobs: no new jobs; $then.',
      );
    }
  }

  /// The engine renewed the leases it lists until a lease length from now.
  void _acknowledged(HeartbeatAckFrame frame) {
    final now = _elapsed();
    for (final grant in frame.leases) {
      if (_active[grant.jobId]?.offer.leaseId == grant.leaseId) {
        _renewed[grant.jobId] = now;
      }
    }
  }

  void _sendHeartbeat() => _sendFrame(
    HeartbeatFrame(leases: [for (final lease in _active.values) lease.ref]),
  );

  Future<void> _probed(ProbeFrame frame) async {
    final results = await _probe.run(frame.commands);
    _sendFrame(ProbeResultFrame(probeId: frame.probeId, results: results));
  }

  /// Says what the engine found this runner offers: after the first probe,
  /// then only when it changes.
  void _found(ProbedFrame frame) {
    final first = _offers == null;
    if (frame == _offers) return;
    _offers = frame;
    final offers = frame.capabilities.isEmpty
        ? 'This runner offers nothing yet, so it will get no jobs. Run: xp '
              'runner doctor'
        : 'The engine runs $_engineVersion; this runner offers '
              '${frame.capabilities.join(', ')}, $slots '
              'slot${slots == 1 ? '' : 's'}.';
    _log(first ? 'Connected. $offers' : offers);
    for (final missing in frame.missing) {
      _log('No ${missing.capability}: ${missing.explanation}');
    }
  }

  // ----------------------------------------------------------------- leases

  void _offered(LeaseOfferFrame offer) {
    String? refusal;
    final unknown = {
      for (final step in offer.steps)
        if (!_stepKinds.contains(step.kind)) step.kind,
    };
    if (_draining) {
      refusal = 'draining';
    } else if (_updateTo != null) {
      refusal = 'updating';
    } else if (unknown.isNotEmpty) {
      refusal = 'unsupported: this runner has no step ${unknown.join(', ')}';
    } else if (_active.length >= slots || _active.containsKey(offer.jobId)) {
      refusal = 'busy';
    } else if (offer.capabilities.contains('ios-sign') &&
        _active.values.any((lease) => lease.needsIosSign)) {
      refusal = 'busy';
    }
    if (refusal != null) {
      _log('Refused job ${offer.jobId}: $refusal.');
      _sendFrame(
        LeaseRejectFrame(
          jobId: offer.jobId,
          leaseId: offer.leaseId,
          reason: refusal,
        ),
      );
      return;
    }
    _sendFrame(LeaseAcceptFrame(jobId: offer.jobId, leaseId: offer.leaseId));
    _log(
      'Took job ${offer.jobId}${offer.name == null ? '' : ' (${offer.name})'}.',
    );
    final outbox = LeaseOutbox(
      jobId: offer.jobId,
      leaseId: offer.leaseId,
      send: _sendFrame,
    );
    final work = _start(offer, outbox, (key) => _requestSecret(offer, key));
    _active[offer.jobId] = _Lease(offer, outbox, work);
    // The offer leased the job for a lease length; the accept is its start.
    _renewed[offer.jobId] = _elapsed();
    _tookJob = true;
    if (oneShot && !_draining) {
      // The engine offers nothing more once the runner says so.
      _draining = true;
      _sendFrame(const DrainFrame());
    }
    unawaited(
      work.finished.whenComplete(() {
        // A job that ended without reporting (it was cancelled) is over; one
        // that reported is over when the engine acknowledges its end.
        if (!outbox.awaitsAcknowledgement) _release(offer.jobId, work);
      }),
    );
  }

  void _ended(DoneAckFrame ack) {
    final lease = _active[ack.jobId];
    if (lease == null) return;
    lease.outbox.doneAcknowledged();
    _log(
      'Job ${ack.jobId} ended: the engine recorded it as ${ack.state.wire}.',
    );
    _release(ack.jobId, lease.work);
  }

  void _release(String jobId, LeaseWork work) {
    if (!identical(_active[jobId]?.work, work)) return;
    _active.remove(jobId);
    _renewed.remove(jobId);
    _checkExit();
  }

  Future<void> _cancelled(CancelFrame frame) async {
    final lease = _active[frame.jobId];
    if (lease == null) return;
    final leaseId = frame.leaseId;
    if (leaseId != null && leaseId != lease.offer.leaseId) return;
    await _end(
      lease,
      'Job ${frame.jobId} was cancelled by the engine: ${frame.reason}',
    );
  }

  /// Stops the job of [lease] and forgets it, with what its outbox held: its
  /// process groups end, its secrets are wiped, nothing more is reported.
  Future<void> _end(_Lease lease, String message) async {
    final jobId = lease.offer.jobId;
    if (!identical(_active[jobId], lease)) return;
    _log(message);
    _active.remove(jobId);
    _renewed.remove(jobId);
    for (final key in _askedSecrets.keys.toList()) {
      if (key.startsWith('$jobId/')) {
        _askedSecrets.remove(key);
        _secrets.remove(key)?.complete(null);
      }
    }
    await lease.work.cancel();
    _checkExit();
  }

  // ---------------------------------------------------------------- secrets

  Future<List<int>?> _requestSecret(LeaseOfferFrame offer, String key) {
    final id = '${offer.jobId}/$key';
    final completer = _secrets.putIfAbsent(id, Completer<List<int>?>.new);
    final frame = _askedSecrets.putIfAbsent(
      id,
      () => SecretRequestFrame(
        jobId: offer.jobId,
        leaseId: offer.leaseId,
        key: key,
      ),
    );
    _sendFrame(frame);
    return completer.future.timeout(
      secretTimeout,
      onTimeout: () {
        _secrets.remove(id);
        _askedSecrets.remove(id);
        throw TimeoutException(
          'The engine did not answer the request for a secret.',
          secretTimeout,
        );
      },
    );
  }

  void _secretValue(SecretValueFrame frame) {
    final id = '${frame.jobId}/${frame.key}';
    _askedSecrets.remove(id);
    final completer = _secrets.remove(id);
    if (completer == null || completer.isCompleted) return;
    try {
      completer.complete(base64Decode(frame.value));
    } on FormatException {
      completer.complete(null);
    }
  }

  void _secretDenied(SecretDeniedFrame frame) {
    final id = '${frame.jobId}/${frame.key}';
    _askedSecrets.remove(id);
    _log('The engine refused a secret of job ${frame.jobId}: ${frame.reason}');
    final completer = _secrets.remove(id);
    if (completer != null && !completer.isCompleted) completer.complete(null);
  }

  // ----------------------------------------------------------------- output

  /// Sends [frame] on the connection that is open, if there is one. A frame
  /// that cannot be sent is not lost: what matters is kept by the outboxes and
  /// sent again after a reconnect.
  void _sendFrame(RunnerFrame frame) {
    final socket = _socket;
    if (socket == null) return;
    try {
      socket.send(jsonEncode(frame.toJson()));
    } on Object {
      // The connection is gone; it ends by itself.
    }
  }

  static String _describe(Object error) => switch (error) {
    final XpClientException e => e.message,
    _ => '$error',
  };
}

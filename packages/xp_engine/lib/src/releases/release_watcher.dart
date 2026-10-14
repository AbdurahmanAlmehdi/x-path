import 'dart:async';

import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/credentials/credential_health_check.dart';
import 'package:xp_engine/src/releases/release_service.dart';
import 'package:xp_engine/src/repositories/event_log.dart';

/// Keeps the releases up to date while `xpd serve` runs.
///
/// It listens to the event log: when a job or one of its steps changes, the
/// release the job belongs to is brought up to date with its jobs (so that
/// `uploaded`, the tag and the pull request show up as they happen). And
/// every [interval] it asks the stores about the releases that wait for them;
/// the service asks a store at most every ten minutes, so a short interval
/// costs nothing.
///
/// [start] polls at once (an engine that was off for a day catches up on
/// start). Polls never overlap.
class ReleaseWatcher {
  /// Creates the watcher.
  ///
  /// [onError] hears about a failure; the next change or poll goes on.
  /// [timers] replaces [Timer.periodic] in tests.
  new({
    required this._events,
    required this._service,
    this.interval = const Duration(minutes: 1),
    this.onError,
    PeriodicTimerFactory? timers,
  }) : _timers = timers ?? Timer.periodic;

  /// How often the stores are due to be asked.
  final Duration interval;

  /// Hears about a failure.
  final void Function(Object error, StackTrace stackTrace)? onError;

  final EventLog _events;
  final ReleaseService _service;
  final PeriodicTimerFactory _timers;
  StreamSubscription<SequencedEvent>? _subscription;
  Timer? _timer;
  var _polling = false;
  Future<void> _tail = Future.value();

  /// Whether [start] was called and [stop] was not.
  bool get isRunning => _timer != null;

  /// Starts listening and polling, and returns when the first poll is done.
  Future<void> start() async {
    if (_timer != null) return;
    _subscription = _events.subscribe().listen(_onEvent);
    _timer = _timers(interval, (_) => unawaited(pollNow()));
    await pollNow();
  }

  /// Asks the stores that are due now, unless a poll is running.
  Future<void> pollNow() async {
    if (_polling) return;
    _polling = true;
    try {
      await _service.pollDue();
    } on Object catch (error, stackTrace) {
      onError?.call(error, stackTrace);
    } finally {
      _polling = false;
    }
  }

  /// Stops listening and polling. A running poll finishes.
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await _subscription?.cancel();
    _subscription = null;
    await _tail;
  }

  void _onEvent(SequencedEvent logged) {
    final jobId = switch (logged.event) {
      JobStateChanged(:final jobId) => jobId,
      JobStepChanged(:final jobId) => jobId,
      _ => null,
    };
    if (jobId == null) return;
    // One at a time, in the order the events came.
    _tail = _tail.then((_) async {
      try {
        await _service.syncJob(jobId);
      } on Object catch (error, stackTrace) {
        onError?.call(error, stackTrace);
      }
    });
  }
}

import 'dart:async';

import 'package:xp_engine/src/credentials/credential_health_check.dart';
import 'package:xp_engine/src/runners/runner_hub.dart';

/// Ends the leases that ran out (`xpd serve`), so that a job whose runner
/// vanished is queued again (or waits for a resume) 90 seconds after the
/// runner's last heartbeat, even if nobody looks at it (D-08).
///
/// [start] sweeps at once, then every [interval]. Sweeps never overlap.
class LeaseSweeper {
  /// Creates the sweeper.
  ///
  /// [onError] hears about a sweep that failed; the next one goes on.
  /// [timers] replaces [Timer.periodic] in tests.
  new({
    required this._hub,
    this.interval = const Duration(seconds: 10),
    this.onError,
    PeriodicTimerFactory? timers,
  }) : _timers = timers ?? Timer.periodic;

  /// How often leases are swept.
  final Duration interval;

  /// Hears about a failed sweep.
  final void Function(Object error, StackTrace stackTrace)? onError;

  final RunnerHub _hub;
  final PeriodicTimerFactory _timers;
  Timer? _timer;
  var _running = false;

  /// Whether [start] was called and [stop] was not.
  bool get isRunning => _timer != null;

  /// Starts the schedule and returns when the first sweep is done.
  Future<void> start() async {
    if (_timer != null) return;
    _timer = _timers(interval, (_) => unawaited(runNow()));
    await runNow();
  }

  /// Sweeps now, unless a sweep is running.
  Future<void> runNow() async {
    if (_running) return;
    _running = true;
    try {
      await _hub.sweep();
    } on Object catch (error, stackTrace) {
      onError?.call(error, stackTrace);
    } finally {
      _running = false;
    }
  }

  /// Stops the schedule. A running sweep finishes.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}

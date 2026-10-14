import 'dart:async';

import 'package:xp_engine/src/approvals/approval_service.dart';
import 'package:xp_engine/src/credentials/credential_health_check.dart';

/// Expires the approvals nobody decided in time (`xpd serve`), so that a job
/// that waits at a gate fails when its 24 hours are up even if nobody looks
/// at it (D-13).
///
/// [start] sweeps at once (an engine that was off for a day catches up on
/// start), then every [interval]. Sweeps never overlap.
class ApprovalSweeper {
  /// Creates the sweeper.
  ///
  /// [onError] hears about a sweep that failed; the next one goes on.
  /// [timers] replaces [Timer.periodic] in tests.
  new({
    required this._service,
    this.interval = const Duration(minutes: 1),
    this.onError,
    PeriodicTimerFactory? timers,
  }) : _timers = timers ?? Timer.periodic;

  /// How often approvals are swept.
  final Duration interval;

  /// Hears about a failed sweep.
  final void Function(Object error, StackTrace stackTrace)? onError;

  final ApprovalService _service;
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
      await _service.sweep();
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

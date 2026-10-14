import 'dart:async';

import 'package:xp_engine/src/clock/clock.dart';
import 'package:xp_engine/src/credentials/credential_health_check.dart';
import 'package:xp_engine/src/housekeeping/housekeeping_service.dart';

/// Prunes the logs once a day (D-24): at the start if the last pruning was a
/// day ago or never, and then every [interval].
class HousekeepingSchedule {
  /// Creates the schedule.
  ///
  /// [timers] makes the periodic timer; tests pass their own.
  new({
    required this._service,
    required this._clock,
    this.interval = const Duration(hours: 24),
    this.onError,
    PeriodicTimerFactory? timers,
  }) : _timers = timers ?? Timer.periodic;

  /// How often the logs are pruned.
  final Duration interval;

  /// Hears about a pruning that failed; the schedule goes on.
  final void Function(Object error, StackTrace stackTrace)? onError;

  final HousekeepingService _service;
  final Clock _clock;
  final PeriodicTimerFactory _timers;
  Timer? _timer;
  var _running = false;

  /// Whether the schedule runs.
  bool get isRunning => _timer != null;

  /// Starts the timer, and prunes now if a pruning is due. Does nothing if it
  /// runs already.
  Future<void> start() async {
    if (_timer != null) return;
    _timer = _timers(interval, (_) => unawaited(runNow()));
    try {
      final last = await _service.lastLogPrune();
      if (last == null || !last.add(interval).isAfter(_clock.now())) {
        await runNow();
      }
    } on Object catch (error, stackTrace) {
      onError?.call(error, stackTrace);
    }
  }

  /// Prunes the logs now, unless a pruning is under way.
  Future<void> runNow() async {
    if (_running) return;
    _running = true;
    try {
      await _service.pruneLogs();
    } on Object catch (error, stackTrace) {
      onError?.call(error, stackTrace);
    } finally {
      _running = false;
    }
  }

  /// Stops the timer. A pruning under way finishes.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}

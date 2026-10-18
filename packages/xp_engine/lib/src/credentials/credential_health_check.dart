import 'dart:async';

import 'package:xp_engine/src/clock/clock.dart';
import 'package:xp_engine/src/credentials/credential_repository.dart';
import 'package:xp_engine/src/credentials/credential_service.dart';

/// Starts a timer that calls its callback every [period].
typedef PeriodicTimerFactory = Timer Function(
  Duration period,
  void Function(Timer timer) callback,
);

/// Checks every credential and every assignment once a day (`xpd serve`), so
/// that an expired ASC key, a revoked app-specific password or a key that
/// lost access to an app shows up before a release needs it: the
/// `credentials` guard check fails a job on what is recorded.
///
/// [start] checks at once if any credential or assignment was not checked
/// within the last [interval] (an engine that was off for a day catches up
/// on start), then
/// every [interval]. Checks never overlap.
class CredentialHealthCheck {
  /// Creates the health check.
  ///
  /// [onError] hears about a run that failed (locked secrets, a bug in a
  /// verifier); the next run goes on. [timers] replaces [Timer.periodic] in
  /// tests.
  new({
    required this._service,
    required this._repository,
    required this._clock,
    this.interval = const Duration(hours: 24),
    this.onError,
    PeriodicTimerFactory? timers,
  }) : _timers = timers ?? Timer.periodic;

  /// How often credentials are checked.
  final Duration interval;

  /// Hears about a failed run.
  final void Function(Object error, StackTrace stackTrace)? onError;

  final CredentialService _service;
  final CredentialRepository _repository;
  final Clock _clock;
  final PeriodicTimerFactory _timers;
  Timer? _timer;
  var _running = false;

  /// Whether [start] was called and [stop] was not.
  bool get isRunning => _timer != null;

  /// Starts the schedule and returns when the first check, if one was due, is
  /// done.
  Future<void> start() async {
    if (_timer != null) return;
    _timer = _timers(interval, (_) => unawaited(runNow()));
    try {
      if (await _isDue()) await runNow();
    } on Object catch (error, stackTrace) {
      onError?.call(error, stackTrace);
    }
  }

  /// Checks every credential now, unless a check is running.
  Future<void> runNow() async {
    if (_running) return;
    _running = true;
    try {
      await _service.checkAll();
    } on Object catch (error, stackTrace) {
      onError?.call(error, stackTrace);
    } finally {
      _running = false;
    }
  }

  /// Stops the schedule. A running check finishes.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<bool> _isDue() async {
    final cutoff = _clock.now().subtract(interval);
    final checks = [
      for (final record in await _repository.list()) record.check,
      for (final assignment in await _repository.assignments())
        assignment.check,
    ];
    for (final check in checks) {
      final checked = check.checkedAt;
      if (checked == null || !checked.isAfter(cutoff)) return true;
    }
    return false;
  }
}

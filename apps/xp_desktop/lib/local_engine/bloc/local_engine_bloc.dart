import 'dart:developer' as developer;

import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:xp_macos_services/xp_macos_services.dart';
import 'package:xp_repositories/xp_repositories.dart';

sealed class LocalEngineEvent extends Equatable {
  const new();

  @override
  List<Object?> get props => [];
}

/// Asks whether the engine on this Mac answers now (Settings ▸ About).
final class LocalEngineChecked extends LocalEngineEvent {
  const new();
}

/// The app reached the engine on this Mac: whatever was wrong is over, and
/// the next time it stops answering is a new episode.
final class LocalEngineReachable extends LocalEngineEvent {
  const new();
}

/// Starts the engine on this Mac and reconnects the app to it. The owner
/// asks with "Start engine"; the app asks on its own ([automatic]) when the
/// engine is unreachable at launch or later, once per episode. A new app
/// token, if the engine refused the old one, is called [tokenName].
final class LocalEngineStartRequested extends LocalEngineEvent {
  const new({required this.tokenName, this.automatic = false});

  final String tokenName;
  final bool automatic;

  @override
  List<Object?> get props => [tokenName, automatic];
}

/// Opens System Settings at Login Items.
final class LocalEngineLoginItemsRequested extends LocalEngineEvent {
  const new();
}

/// What starting the engine is doing.
enum LocalEngineProgress { idle, starting, started, failed }

/// Why the engine on this Mac did not start.
enum LocalEngineFailure {
  /// This copy of the app has no engine inside it (or macOS cannot find its
  /// login item, as for a copy outside Applications).
  noEngine,

  /// The login item waits for the owner in System Settings ▸ General ▸ Login
  /// Items.
  needsApproval,

  /// macOS is older than 13.
  unsupported,

  /// macOS refused to register the login item; [LocalEngineState.message]
  /// says why.
  refused,

  /// The engine did not answer in time after it was registered.
  timedOut,

  /// The engine runs, but refused the app's token and could not make a new
  /// one; [LocalEngineState.message] says why.
  token,
}

class LocalEngineState extends Equatable {
  const new({
    this.running,
    this.progress = LocalEngineProgress.idle,
    this.failure,
    this.message,
    this.tokenRenewed = false,
  });

  /// Whether the engine on this Mac answers; `null` until known.
  final bool? running;

  final LocalEngineProgress progress;

  /// Why the last start failed.
  final LocalEngineFailure? failure;

  /// What macOS or the engine said, for [LocalEngineFailure.refused] and
  /// [LocalEngineFailure.token].
  final String? message;

  /// Whether the last start made a new app token (the engine refused the
  /// old one), so the app opens a new session instead of checking again.
  final bool tokenRenewed;

  bool get starting => progress == LocalEngineProgress.starting;

  @override
  List<Object?> get props => [
    running,
    progress,
    failure,
    message,
    tokenRenewed,
  ];
}

/// Keeps the engine on this Mac running: brings it back when launchd lost
/// it (a `launchctl bootout`) or its login item names a copy of the app
/// that moved, then lets the app reconnect with the token it has.
///
/// The app asks on its own once per episode (from the moment the engine is
/// unreachable until it answers again), and waits longer after each
/// automatic try that failed, so it never loops; the owner can always ask
/// with "Start engine".
class LocalEngineBloc extends Bloc<LocalEngineEvent, LocalEngineState> {
  new({
    required this._agent,
    required this._localEngine,
    required this._engines,
    this._now = DateTime.now,
    this._log = _defaultLog,
    this.startTimeout = const Duration(seconds: 30),
    this.firstBackoff = const Duration(minutes: 1),
    this.maxBackoff = const Duration(minutes: 30),
  }) : _backoff = firstBackoff,
       super(const LocalEngineState()) {
    on<LocalEngineChecked>(_onChecked, transformer: droppable());
    on<LocalEngineReachable>(_onReachable);
    on<LocalEngineStartRequested>(_onStart, transformer: droppable());
    on<LocalEngineLoginItemsRequested>(
      (_, _) => _agent.openLoginItemsSettings(),
      transformer: droppable(),
    );
  }

  final EngineAgent _agent;
  final LocalEngine _localEngine;
  final EnginesRepository _engines;
  final DateTime Function() _now;
  final void Function(String message) _log;

  /// How long the engine has to answer after it was registered.
  final Duration startTimeout;

  /// How long after a failed automatic try the next one may come; it
  /// doubles after each failed try, up to [maxBackoff].
  final Duration firstBackoff;
  final Duration maxBackoff;

  Duration _backoff;
  DateTime? _lastAutomatic;
  var _triedThisEpisode = false;

  static void _defaultLog(String message) =>
      developer.log(message, name: 'xpath.local_engine');

  Future<void> _onChecked(
    LocalEngineChecked event,
    Emitter<LocalEngineState> emit,
  ) async {
    final running = await _engines.waitForLocalEngine(timeout: Duration.zero);
    if (state.starting) return;
    emit(_with(running: running));
  }

  void _onReachable(
    LocalEngineReachable event,
    Emitter<LocalEngineState> emit,
  ) {
    _triedThisEpisode = false;
    emit(const LocalEngineState(running: true));
  }

  Future<void> _onStart(
    LocalEngineStartRequested event,
    Emitter<LocalEngineState> emit,
  ) async {
    if (event.automatic && !_mayTryOnItsOwn()) return;
    emit(_with(progress: LocalEngineProgress.starting));
    final failure = await _start(event.tokenName, emit);
    if (event.automatic) {
      _backoff = failure == null
          ? firstBackoff
          : _backoff * 2 > maxBackoff
          ? maxBackoff
          : _backoff * 2;
    }
  }

  bool _mayTryOnItsOwn() {
    if (_triedThisEpisode) {
      _log('Not starting the engine again on its own: tried once already.');
      return false;
    }
    final now = _now();
    final last = _lastAutomatic;
    if (last != null && now.difference(last) < _backoff) {
      _log(
        'Not starting the engine on its own: the last try was less than '
        '${_backoff.inMinutes} min ago.',
      );
      return false;
    }
    _triedThisEpisode = true;
    _lastAutomatic = now;
    _log('The engine on this Mac does not answer: starting it.');
    return true;
  }

  /// Starts the engine and returns why it failed, or `null`.
  Future<LocalEngineFailure?> _start(
    String tokenName,
    Emitter<LocalEngineState> emit,
  ) async {
    // It may answer already (it was only slow): then leave it running.
    if (!await _engines.waitForLocalEngine(timeout: Duration.zero)) {
      if (!_localEngine.isBundled) {
        return _fail(emit, LocalEngineFailure.noEngine);
      }
      final AgentStatus status;
      try {
        status = await _agent.restart();
      } on MacosServiceException catch (error) {
        return _fail(emit, LocalEngineFailure.refused, error.message);
      }
      _log('The login item of the engine is ${status.name}.');
      switch (status) {
        case AgentStatus.enabled:
          break;
        case AgentStatus.requiresApproval:
          return _fail(emit, LocalEngineFailure.needsApproval);
        case AgentStatus.unsupported:
          return _fail(emit, LocalEngineFailure.unsupported);
        case AgentStatus.notFound || AgentStatus.notRegistered:
          return _fail(emit, LocalEngineFailure.noEngine);
      }
      if (!await _engines.waitForLocalEngine(timeout: startTimeout)) {
        return _fail(emit, LocalEngineFailure.timedOut);
      }
    }
    final bool renewed;
    try {
      renewed = await _renewTokenIfRefused(tokenName);
    } on Exception catch (error) {
      return _fail(emit, LocalEngineFailure.token, switch (error) {
        LocalEngineException(:final message) => message,
        MacosServiceException(:final message) => message,
        _ => errorMessage(error),
      });
    }
    _log(
      renewed
          ? 'The engine runs; it refused the old token, so there is a new '
                'one.'
          : 'The engine runs; reconnecting with the token the app has.',
    );
    emit(
      LocalEngineState(
        running: true,
        progress: LocalEngineProgress.started,
        tokenRenewed: renewed,
      ),
    );
    return null;
  }

  /// Keeps the token the app has unless the engine refuses it (or there is
  /// none): the engine's database is the same, so is its token. Whether it
  /// made a new one.
  Future<bool> _renewTokenIfRefused(String tokenName) async {
    final String? token;
    try {
      token = await _engines.token(localEngineId);
    } on Exception {
      // A locked Keychain: the connection says so; no new token for that.
      return false;
    }
    if (token != null) {
      try {
        await _engines.check(localEngineUrl, token);
        return false;
      } on EngineCheckException catch (error) {
        if (error.failure != EngineCheckFailure.tokenRejected) return false;
      }
    }
    final fresh = await _localEngine.createAppToken(name: tokenName);
    await _engines.saveLocalToken(fresh);
    return true;
  }

  LocalEngineFailure _fail(
    Emitter<LocalEngineState> emit,
    LocalEngineFailure failure, [
    String? message,
  ]) {
    _log(
      'Could not start the engine on this Mac: ${failure.name}'
      '${message == null ? '' : ' ($message)'}.',
    );
    emit(
      LocalEngineState(
        running: false,
        progress: LocalEngineProgress.failed,
        failure: failure,
        message: message,
      ),
    );
    return failure;
  }

  LocalEngineState _with({bool? running, LocalEngineProgress? progress}) =>
      LocalEngineState(
        running: running ?? state.running,
        progress: progress ?? state.progress,
        failure: progress == null ? state.failure : null,
        message: progress == null ? state.message : null,
      );
}

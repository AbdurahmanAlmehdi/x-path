import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:xp_desktop/app/app_services.dart';
import 'package:xp_repositories/xp_repositories.dart';

part 'engine_connection_event.dart';
part 'engine_connection_state.dart';

/// Owns the active engine: its session (client, events, cache) and its
/// status.
///
/// Switching engines closes the old session, which ends every stream the
/// repositories gave out, and opens a new one; the app keys its repository
/// subtree on the session, so every screen below starts over with the new
/// engine's streams.
class EngineConnectionBloc
    extends Bloc<EngineConnectionEvent, EngineConnectionState> {
  new({required this._engines, required this._openSession})
    : super(const EngineConnectionState()) {
    on<EngineConnectRequest>(_onConnect, transformer: restartable());
    on<EngineCheckRequested>(_onCheck, transformer: droppable());
  }

  final EnginesRepository _engines;
  final SessionFactory _openSession;

  Future<void> _onConnect(
    EngineConnectRequest event,
    Emitter<EngineConnectionState> emit,
  ) async {
    switch (event) {
      case EngineSelected(:final engineId):
        await _engines.select(engineId);
      case EngineRemoved(:final engineId):
        await _engines.remove(engineId);
      case EngineConnectionStarted() || EnginesChanged():
        break;
    }
    final list = await _engines.load();
    final active = list.active;
    var session = state.session;

    // A new list, a pick or a different active engine opens a new session
    // (the token may have changed); removing another engine keeps it.
    final reconnect =
        !state.loaded ||
        active != state.active ||
        event is EnginesChanged ||
        event is EngineSelected;
    if (reconnect) {
      await session?.close();
      session = null;
      if (active != null) {
        final token = await _token(active.id);
        if (token != null) session = _openSession(active, token);
      }
      emit(
        EngineConnectionState(
          loaded: true,
          engines: list.engines,
          active: active,
          session: session,
          status: active != null && session == null
              ? EngineStatus.rejected
              : EngineStatus.connecting,
        ),
      );
      if (session == null) return;
      final statuses = emit.forEach<EngineStatus>(
        session.statusChanges,
        onData: (status) => state.copyWith(status: status),
      );
      await session.start();
      await statuses;
    } else {
      emit(state.copyWith(engines: list.engines));
      if (session == null) return;
      emit(state.copyWith(status: session.status));
      await emit.forEach<EngineStatus>(
        session.statusChanges,
        onData: (status) => state.copyWith(status: status),
      );
    }
  }

  Future<String?> _token(String engineId) async {
    try {
      return await _engines.token(engineId);
    } on Exception {
      // A locked or unreadable Keychain: the app says the token is missing.
      return null;
    }
  }

  Future<void> _onCheck(
    EngineCheckRequested event,
    Emitter<EngineConnectionState> emit,
  ) async => await state.session?.check();

  @override
  Future<void> close() async {
    await state.session?.close();
    await super.close();
  }
}

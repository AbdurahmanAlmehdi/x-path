part of 'engine_connection_bloc.dart';

class EngineConnectionState extends Equatable {
  const new({
    this.loaded = false,
    this.engines = const [],
    this.active,
    this.session,
    this.status = EngineStatus.connecting,
  });

  /// Whether the engine list was read.
  final bool loaded;

  /// The engines the app knows.
  final List<EngineProfile> engines;

  /// The engine the app shows.
  final EngineProfile? active;

  /// The session with [active]; `null` without an engine, or when its token
  /// is missing.
  final EngineSession? session;

  /// How the connection to [active] stands.
  final EngineStatus status;

  /// Whether the active engine has no usable token.
  bool get missingToken => active != null && session == null;

  EngineConnectionState copyWith({
    List<EngineProfile>? engines,
    EngineStatus? status,
  }) => EngineConnectionState(
    loaded: loaded,
    engines: engines ?? this.engines,
    active: active,
    session: session,
    status: status ?? this.status,
  );

  @override
  List<Object?> get props => [loaded, engines, active, session, status];
}

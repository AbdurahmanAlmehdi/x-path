part of 'engine_connection_bloc.dart';

sealed class EngineConnectionEvent extends Equatable {
  const new();

  @override
  List<Object?> get props => [];
}

/// Asks for the engine list again and (re)connects to the active engine.
/// Every subtype goes through one `restartable` handler, so a new request
/// cancels what the last one was still doing.
sealed class EngineConnectRequest extends EngineConnectionEvent {
  const new();
}

/// The app started.
final class EngineConnectionStarted extends EngineConnectRequest {
  const new();
}

/// The engine list changed elsewhere (an engine was added).
final class EnginesChanged extends EngineConnectRequest {
  const new();
}

/// The user switched to [engineId].
final class EngineSelected extends EngineConnectRequest {
  const new(this.engineId);

  final String engineId;

  @override
  List<Object?> get props => [engineId];
}

/// The user removed [engineId].
final class EngineRemoved extends EngineConnectRequest {
  const new(this.engineId);

  final String engineId;

  @override
  List<Object?> get props => [engineId];
}

/// The user asked to check the engine now (the banner's Retry).
final class EngineCheckRequested extends EngineConnectionEvent {
  const new();
}

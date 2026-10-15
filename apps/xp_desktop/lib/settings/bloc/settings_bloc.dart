import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_macos_services/xp_macos_services.dart';
import 'package:xp_repositories/xp_repositories.dart';

sealed class SettingsEvent extends Equatable {
  const new();

  @override
  List<Object?> get props => [];
}

/// Reads the versions and where the engine's login item stands.
final class SettingsStarted extends SettingsEvent {
  const new();
}

class SettingsState extends Equatable {
  const new({
    this.loaded = false,
    this.appVersion,
    this.agentStatus,
    this.engineVersion,
    this.engineError,
  });

  /// Whether everything was asked once.
  final bool loaded;

  /// The app's version, `0.0.1 (1)`.
  final String? appVersion;

  /// Where the LaunchAgent of the engine on this Mac stands.
  final AgentStatus? agentStatus;

  /// The version of the engine the app shows.
  final VersionResponse? engineVersion;

  /// Why [engineVersion] could not be read.
  final String? engineError;

  @override
  List<Object?> get props => [
    loaded,
    appVersion,
    agentStatus,
    engineVersion,
    engineError,
  ];
}

/// The "About" of the settings: the app's version, the engine's, and the
/// login item of the engine on this Mac.
class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  new({required this._app, required this._agent, required this._settings})
    : super(const SettingsState()) {
    on<SettingsStarted>(_onStarted, transformer: restartable());
  }

  final RunningApp _app;
  final EngineAgent _agent;
  final SettingsRepository _settings;

  Future<void> _onStarted(
    SettingsStarted event,
    Emitter<SettingsState> emit,
  ) async {
    final appVersion = await _app.version();
    final agent = await _agent.status();
    VersionResponse? engineVersion;
    String? engineError;
    try {
      engineVersion = await _settings.engineVersion();
    } on Exception catch (error) {
      engineError = errorMessage(error);
    }
    emit(
      SettingsState(
        loaded: true,
        appVersion: appVersion,
        agentStatus: agent,
        engineVersion: engineVersion,
        engineError: engineError,
      ),
    );
  }
}

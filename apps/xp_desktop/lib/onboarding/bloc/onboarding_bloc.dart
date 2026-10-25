import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:xp_macos_services/xp_macos_services.dart';
import 'package:xp_repositories/xp_repositories.dart';

sealed class OnboardingEvent extends Equatable {
  const new();

  @override
  List<Object?> get props => [];
}

/// Reads where the engine and the `xp` link stand already.
final class OnboardingStarted extends OnboardingEvent {
  const new();
}

/// Registers the engine's LaunchAgent and connects the app to it as
/// [engineName], with a token called [tokenName].
final class OnboardingEngineRequested extends OnboardingEvent {
  const new({required this.engineName, required this.tokenName});

  final String engineName;
  final String tokenName;

  @override
  List<Object?> get props => [engineName, tokenName];
}

/// Opens System Settings at Login Items.
final class OnboardingLoginItemsRequested extends OnboardingEvent {
  const new();
}

/// Links `xp` into the `PATH`.
final class OnboardingCliRequested extends OnboardingEvent {
  const new();
}

/// Checks the tools.
final class OnboardingToolsRequested extends OnboardingEvent {
  const new();
}

/// What a step is doing.
enum StepProgress { idle, working, done, failed }

class OnboardingState extends Equatable {
  const new({
    this.engine = StepProgress.idle,
    this.agentStatus,
    this.engineError,
    this.tokenError,
    this.cli = StepProgress.idle,
    this.cliLink,
    this.tools = StepProgress.idle,
    this.toolChecks = const [],
  });

  final StepProgress engine;

  /// Where the LaunchAgent stands, once known.
  final AgentStatus? agentStatus;

  /// What macOS said when it refused to register the agent.
  final String? engineError;

  /// What the engine said when it could not make the app's token.
  final String? tokenError;

  final StepProgress cli;
  final CliLink? cliLink;

  final StepProgress tools;
  final List<ToolCheck> toolChecks;

  /// Whether the engine on this Mac is saved with a token, so the app can
  /// open it.
  bool get connected => engine == StepProgress.done;

  OnboardingState copyWith({
    StepProgress? engine,
    AgentStatus? agentStatus,
    String? engineError,
    String? tokenError,
    StepProgress? cli,
    CliLink? cliLink,
    StepProgress? tools,
    List<ToolCheck>? toolChecks,
  }) => OnboardingState(
    engine: engine ?? this.engine,
    agentStatus: agentStatus ?? this.agentStatus,
    engineError: engineError,
    tokenError: tokenError,
    cli: cli ?? this.cli,
    cliLink: cliLink ?? this.cliLink,
    tools: tools ?? this.tools,
    toolChecks: toolChecks ?? this.toolChecks,
  );

  @override
  List<Object?> get props => [
    engine,
    agentStatus,
    engineError,
    tokenError,
    cli,
    cliLink,
    tools,
    toolChecks,
  ];
}

/// The three steps of setting up this Mac: run the engine (and connect the
/// app to it), link `xp`, check the tools. Every step can be repeated.
class OnboardingBloc extends Bloc<OnboardingEvent, OnboardingState> {
  new({
    required this._agent,
    required this._localEngine,
    required this._engines,
    required this._linker,
    required this._tools,
  }) : super(const OnboardingState()) {
    on<OnboardingStarted>(_onStarted, transformer: droppable());
    on<OnboardingEngineRequested>(_onEngine, transformer: droppable());
    on<OnboardingLoginItemsRequested>(
      (_, _) => _agent.openLoginItemsSettings(),
      transformer: droppable(),
    );
    on<OnboardingCliRequested>(_onCli, transformer: droppable());
    on<OnboardingToolsRequested>(_onTools, transformer: droppable());
  }

  final EngineAgent _agent;
  final LocalEngine _localEngine;
  final EnginesRepository _engines;
  final CliLinker _linker;
  final ToolChecker _tools;

  Future<void> _onStarted(
    OnboardingStarted event,
    Emitter<OnboardingState> emit,
  ) async {
    final agent = await _agent.status();
    final link = await _linker.status();
    final saved = await _hasLocalToken();
    emit(
      state.copyWith(
        agentStatus: agent,
        engine: agent == AgentStatus.enabled && saved
            ? StepProgress.done
            : StepProgress.idle,
        cliLink: link,
        cli: link.state == CliLinkState.linked
            ? StepProgress.done
            : StepProgress.idle,
      ),
    );
    add(const OnboardingToolsRequested());
  }

  Future<void> _onEngine(
    OnboardingEngineRequested event,
    Emitter<OnboardingState> emit,
  ) async {
    emit(state.copyWith(engine: StepProgress.working));
    final AgentStatus status;
    try {
      status = await _agent.register();
    } on MacosServiceException catch (error) {
      emit(
        state.copyWith(engine: StepProgress.failed, engineError: error.message),
      );
      return;
    }
    if (status != AgentStatus.enabled) {
      emit(state.copyWith(engine: StepProgress.failed, agentStatus: status));
      return;
    }
    try {
      if (!await _hasLocalToken()) {
        final token = await _localEngine.createAppToken(name: event.tokenName);
        await _engines.saveLocal(name: event.engineName, token: token);
      }
      emit(state.copyWith(engine: StepProgress.done, agentStatus: status));
    } on Exception catch (error) {
      emit(
        state.copyWith(
          engine: StepProgress.failed,
          agentStatus: status,
          tokenError: switch (error) {
            LocalEngineException(:final message) => message,
            MacosServiceException(:final message) => message,
            _ => errorMessage(error),
          },
        ),
      );
    }
  }

  Future<bool> _hasLocalToken() async {
    try {
      return await _engines.token(localEngineId) != null;
    } on Exception {
      return false;
    }
  }

  Future<void> _onCli(
    OnboardingCliRequested event,
    Emitter<OnboardingState> emit,
  ) async {
    emit(state.copyWith(cli: StepProgress.working));
    final link = await _linker.link();
    emit(
      state.copyWith(
        cli: link.state == CliLinkState.linked
            ? StepProgress.done
            : StepProgress.failed,
        cliLink: link,
      ),
    );
  }

  Future<void> _onTools(
    OnboardingToolsRequested event,
    Emitter<OnboardingState> emit,
  ) async {
    emit(state.copyWith(tools: StepProgress.working));
    final checks = await _tools.check();
    emit(
      state.copyWith(
        tools: checks.every((check) => check.found || !check.tool.required)
            ? StepProgress.done
            : StepProgress.failed,
        toolChecks: checks,
      ),
    );
  }
}

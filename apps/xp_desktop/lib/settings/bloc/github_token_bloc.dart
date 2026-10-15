import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_repositories/xp_repositories.dart';

sealed class GitHubTokenEvent extends Equatable {
  const new();

  @override
  List<Object?> get props => [];
}

/// Asks the engine whether it has its GitHub token, and what GitHub says.
final class GitHubTokenRequested extends GitHubTokenEvent {
  const new();
}

/// Checks [token] with GitHub on the engine, then stores it there.
final class GitHubTokenSaved extends GitHubTokenEvent {
  const new(this.token);

  final String token;

  @override
  List<Object?> get props => [token];

  @override
  String toString() => 'GitHubTokenSaved(<token>)';
}

/// Takes the token of the GitHub CLI of the engine machine.
final class GitHubTokenImported extends GitHubTokenEvent {
  const new();
}

/// Forgets the engine's token.
final class GitHubTokenCleared extends GitHubTokenEvent {
  const new();
}

/// What the GitHub section is doing.
enum GitHubTokenCommand { none, loading, saving, importing, clearing }

class GitHubTokenState extends Equatable {
  const new({
    this.command = GitHubTokenCommand.none,
    this.status,
    this.error,
    this.saved = 0,
  });

  final GitHubTokenCommand command;

  /// What the engine said last, once it said something.
  final GitHubTokenStatus? status;

  /// What the engine said when a request failed.
  final String? error;

  /// How many times a token was stored; the field clears when it grows.
  final int saved;

  /// Whether the engine answered that it has no token, or one GitHub
  /// refuses: adding a project fails then.
  bool get needsToken =>
      status != null &&
      (!status!.stored || status!.status == CredentialStatus.rejected);

  bool get busy => command != GitHubTokenCommand.none;

  @override
  List<Object?> get props => [command, status, error, saved];
}

/// The engine's GitHub token, which adding a project needs: its status,
/// saving one (pasted or from the GitHub CLI) and removing it. The token
/// never comes back from the engine.
class GitHubTokenBloc extends Bloc<GitHubTokenEvent, GitHubTokenState> {
  new({required this._settings}) : super(const GitHubTokenState()) {
    on<GitHubTokenRequested>(_onRequested, transformer: restartable());
    on<GitHubTokenSaved>(
      (event, emit) => _run(
        emit,
        GitHubTokenCommand.saving,
        () => _settings.setGitHubToken(event.token),
        stored: true,
      ),
      transformer: droppable(),
    );
    on<GitHubTokenImported>(
      (event, emit) => _run(
        emit,
        GitHubTokenCommand.importing,
        _settings.importGitHubToken,
        stored: true,
      ),
      transformer: droppable(),
    );
    on<GitHubTokenCleared>(
      (event, emit) => _run(emit, GitHubTokenCommand.clearing, () async {
        await _settings.clearGitHubToken();
        return const GitHubTokenStatus(stored: false);
      }),
      transformer: droppable(),
    );
  }

  final SettingsRepository _settings;

  Future<void> _onRequested(
    GitHubTokenRequested event,
    Emitter<GitHubTokenState> emit,
  ) => _run(emit, GitHubTokenCommand.loading, _settings.gitHubToken);

  Future<void> _run(
    Emitter<GitHubTokenState> emit,
    GitHubTokenCommand command,
    Future<GitHubTokenStatus> Function() request, {
    bool stored = false,
  }) async {
    emit(
      GitHubTokenState(
        command: command,
        status: state.status,
        saved: state.saved,
      ),
    );
    try {
      final status = await request();
      emit(
        GitHubTokenState(
          status: status,
          saved: stored ? state.saved + 1 : state.saved,
        ),
      );
    } on Exception catch (error) {
      emit(
        GitHubTokenState(
          status: state.status,
          error: errorMessage(error),
          saved: state.saved,
        ),
      );
    }
  }
}

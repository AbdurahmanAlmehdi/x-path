import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_repositories/xp_repositories.dart';

sealed class RunnerUrlEvent extends Equatable {
  const new();

  @override
  List<Object?> get props => [];
}

/// Asks the engine for the runner URL.
final class RunnerUrlRequested extends RunnerUrlEvent {
  const new();
}

/// Sets the runner URL to [url].
final class RunnerUrlSaved extends RunnerUrlEvent {
  const new(this.url);

  final String url;

  @override
  List<Object?> get props => [url];
}

/// Forgets the runner URL.
final class RunnerUrlCleared extends RunnerUrlEvent {
  const new();
}

/// What the runner URL field is doing.
enum RunnerUrlCommand { none, loading, saving, clearing }

class RunnerUrlState extends Equatable {
  const new({
    this.command = RunnerUrlCommand.none,
    this.url,
    this.error,
    this.saved = 0,
  });

  final RunnerUrlCommand command;

  /// What the engine said last, once it said something.
  final RunnerUrl? url;

  /// What the engine said when a request failed.
  final String? error;

  /// How many times a URL was stored; the field clears when it grows.
  final int saved;

  bool get busy => command != RunnerUrlCommand.none;

  @override
  List<Object?> get props => [command, url, error, saved];
}

/// The runner URL: the address runners reach the engine at, which pairing
/// commands carry. Reading it, setting it and clearing it.
class RunnerUrlBloc extends Bloc<RunnerUrlEvent, RunnerUrlState> {
  new({required this._runners}) : super(const RunnerUrlState()) {
    on<RunnerUrlRequested>(
      (event, emit) => _run(emit, RunnerUrlCommand.loading, _runners.runnerUrl),
      transformer: restartable(),
    );
    on<RunnerUrlSaved>(
      (event, emit) => _run(
        emit,
        RunnerUrlCommand.saving,
        () => _runners.setRunnerUrl(event.url.trim()),
        stored: true,
      ),
      transformer: droppable(),
    );
    on<RunnerUrlCleared>(
      (event, emit) => _run(
        emit,
        RunnerUrlCommand.clearing,
        () => _runners.setRunnerUrl(null),
        stored: true,
      ),
      transformer: droppable(),
    );
  }

  final RunnersRepository _runners;

  Future<void> _run(
    Emitter<RunnerUrlState> emit,
    RunnerUrlCommand command,
    Future<RunnerUrl> Function() request, {
    bool stored = false,
  }) async {
    emit(RunnerUrlState(command: command, url: state.url, saved: state.saved));
    try {
      final url = await request();
      emit(
        RunnerUrlState(url: url, saved: stored ? state.saved + 1 : state.saved),
      );
    } on Exception catch (error) {
      emit(
        RunnerUrlState(
          url: state.url,
          error: errorMessage(error),
          saved: state.saved,
        ),
      );
    }
  }
}

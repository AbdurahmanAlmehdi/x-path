import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_repositories/xp_repositories.dart';

sealed class RunnersEvent extends Equatable {
  const new();

  @override
  List<Object?> get props => [];
}

/// Starts following the runners of the engine.
final class RunnersSubscriptionRequested extends RunnersEvent {
  const new();
}

/// Revokes [runnerId].
final class RunnerRevokeRequested extends RunnersEvent {
  const new(this.runnerId);

  final String runnerId;

  @override
  List<Object?> get props => [runnerId];
}

class RunnersState extends Equatable {
  const new({
    this.loaded = false,
    this.runners = const [],
    this.cached = false,
    this.revoking,
    this.error,
  });

  /// Whether the runners arrived (from the cache or the engine).
  final bool loaded;

  /// Every runner, oldest first, revoked ones included.
  final List<Runner> runners;

  /// Whether [runners] came from the offline cache.
  final bool cached;

  /// The runner being revoked.
  final String? revoking;

  /// What the engine said when the runners could not be read or a revoke
  /// failed.
  final String? error;

  /// The runners that may still run jobs.
  List<Runner> get active => [
    for (final runner in runners)
      if (runner.status != RunnerStatus.revoked) runner,
  ];

  /// The revoked runners.
  List<Runner> get revoked => [
    for (final runner in runners)
      if (runner.status == RunnerStatus.revoked) runner,
  ];

  /// How many connected runners hold a job now.
  int get busy => active
      .where(
        (runner) =>
            runner.status != RunnerStatus.offline && runner.jobIds.isNotEmpty,
      )
      .length;

  RunnersState copyWith({
    bool? loaded,
    List<Runner>? runners,
    bool? cached,
    String? Function()? revoking,
    String? Function()? error,
  }) => RunnersState(
    loaded: loaded ?? this.loaded,
    runners: runners ?? this.runners,
    cached: cached ?? this.cached,
    revoking: revoking == null ? this.revoking : revoking(),
    error: error == null ? this.error : error(),
  );

  @override
  List<Object?> get props => [loaded, runners, cached, revoking, error];
}

/// The runners of the engine (D-08): the runners view and the "busy" count
/// in the sidebar. The runner events bring every change, revokes included.
class RunnersBloc extends Bloc<RunnersEvent, RunnersState> {
  new({required this._runners}) : super(const RunnersState()) {
    on<RunnersSubscriptionRequested>(
      (event, emit) => emit.forEach<Snapshot<List<Runner>>>(
        _runners.watchRunners(),
        onData: (snapshot) => state.copyWith(
          loaded: true,
          runners: snapshot.value,
          cached: snapshot.cached,
        ),
        onError: (error, _) =>
            state.copyWith(loaded: true, error: () => errorMessage(error)),
      ),
      transformer: restartable(),
    );
    on<RunnerRevokeRequested>(_onRevoke, transformer: droppable());
  }

  final RunnersRepository _runners;

  Future<void> _onRevoke(
    RunnerRevokeRequested event,
    Emitter<RunnersState> emit,
  ) async {
    emit(state.copyWith(revoking: () => event.runnerId, error: () => null));
    try {
      await _runners.revoke(event.runnerId);
      emit(state.copyWith(revoking: () => null));
    } on Exception catch (error) {
      emit(
        state.copyWith(revoking: () => null, error: () => errorMessage(error)),
      );
    }
  }
}

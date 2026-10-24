import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_repositories/xp_repositories.dart';

sealed class RunsEvent extends Equatable {
  const new();

  @override
  List<Object?> get props => [];
}

/// Follows the runs of the project, newest first, as the filters say.
final class RunsSubscriptionRequested extends RunsEvent {
  const new();
}

/// Shows only the runs in [state] and of [workflowId]; `null` shows all.
final class RunsFilterChanged extends RunsEvent {
  const new({this.state, this.workflowId});

  final RunState? state;
  final String? workflowId;

  @override
  List<Object?> get props => [state, workflowId];
}

class RunsState extends Equatable {
  const new({
    this.loaded = false,
    this.runs = const [],
    this.cached = false,
    this.workflows = const [],
    this.state,
    this.workflowId,
    this.error,
  });

  /// Whether the runs arrived (from the cache or the engine).
  final bool loaded;

  /// The runs, newest first.
  final List<Run> runs;

  /// Whether [runs] came from the offline cache.
  final bool cached;

  /// The workflows of the project, for their names and the filter.
  final List<WorkflowSummary> workflows;

  /// The state the runs are filtered by, if any.
  final RunState? state;

  /// The workflow the runs are filtered by, if any.
  final String? workflowId;

  /// Why the runs could not be read.
  final String? error;

  /// What the workflow [id] is called: its title, else its name.
  String? workflowName(String id) {
    final workflow = workflows.where((w) => w.id == id).firstOrNull;
    return workflow?.title ?? workflow?.name;
  }

  RunsState copyWith({
    bool? loaded,
    List<Run>? runs,
    bool? cached,
    List<WorkflowSummary>? workflows,
    RunState? Function()? state,
    String? Function()? workflowId,
    String? Function()? error,
  }) => RunsState(
    loaded: loaded ?? this.loaded,
    runs: runs ?? this.runs,
    cached: cached ?? this.cached,
    workflows: workflows ?? this.workflows,
    state: state == null ? this.state : state(),
    workflowId: workflowId == null ? this.workflowId : workflowId(),
    error: error == null ? this.error : error(),
  );

  @override
  List<Object?> get props => [
    loaded,
    runs,
    cached,
    workflows,
    state,
    workflowId,
    error,
  ];
}

/// The runs of one project, newest first, wherever they were dispatched
/// from: the Overview's recent runs and the Runs page with its filters.
class RunsBloc extends Bloc<RunsEvent, RunsState> {
  new({
    required this._jobs,
    required this._workflows,
    required this._projectId,
    this._limit = 20,
  }) : super(const RunsState()) {
    on<RunsSubscriptionRequested>(_onSubscribe, transformer: restartable());
    on<RunsFilterChanged>((event, emit) {
      emit(
        state.copyWith(
          state: () => event.state,
          workflowId: () => event.workflowId,
          loaded: false,
        ),
      );
      add(const RunsSubscriptionRequested());
    });
  }

  final JobsRepository _jobs;
  final WorkflowsRepository _workflows;
  final String _projectId;

  /// How many runs to show.
  final int _limit;

  Future<void> _onSubscribe(
    RunsSubscriptionRequested event,
    Emitter<RunsState> emit,
  ) async {
    if (state.workflows.isEmpty) {
      try {
        final workflows = await _workflows.listWorkflows(_projectId);
        emit(state.copyWith(workflows: workflows));
      } on Exception {
        // The runs show their workflow ids; the connection banner says why.
      }
    }
    await emit.forEach<Snapshot<RunsResponse>>(
      _jobs.watchRuns(
        _projectId,
        workflowId: state.workflowId,
        state: state.state,
        limit: _limit,
      ),
      onData: (snapshot) => state.copyWith(
        loaded: true,
        runs: snapshot.value.runs,
        cached: snapshot.cached,
        error: () => null,
      ),
      onError: (error, _) =>
          state.copyWith(loaded: true, error: () => errorMessage(error)),
    );
  }
}

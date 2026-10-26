import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_repositories/xp_repositories.dart';

sealed class ProjectSettingsEvent extends Equatable {
  const new();
}

/// Reads the gates of [projectId].
final class ProjectSettingsStarted extends ProjectSettingsEvent {
  const new(this.projectId);

  final String projectId;

  @override
  List<Object?> get props => [projectId];
}

/// Releases are based on [branch] from now on.
final class ProjectBaseBranchSaved extends ProjectSettingsEvent {
  const new(this.branch);

  final String branch;

  @override
  List<Object?> get props => [branch];
}

/// The action [action] waits for an approval ([on]) or not.
final class ProjectGateChanged extends ProjectSettingsEvent {
  const new(this.action, {required this.on});

  final String action;
  final bool on;

  @override
  List<Object?> get props => [action, on];
}

/// Removes the project from the engine.
final class ProjectRemoveRequested extends ProjectSettingsEvent {
  const new();

  @override
  List<Object?> get props => [];
}

/// What the page is doing.
enum ProjectSettingsCommand { none, loading, saving, removing }

class ProjectSettingsState extends Equatable {
  const new({
    this.projectId = '',
    this.command = ProjectSettingsCommand.none,
    this.gates,
    this.saved = 0,
    this.removed = false,
    this.error,
  });

  final String projectId;
  final ProjectSettingsCommand command;

  /// Whether each action waits for an approval, once read.
  final Map<String, bool>? gates;

  /// How many times the base branch was saved: a toast says so.
  final int saved;

  /// Whether the project is gone from the engine.
  final bool removed;

  /// What the engine said when a request failed.
  final String? error;

  bool get busy => command != ProjectSettingsCommand.none;

  ProjectSettingsState _with({
    ProjectSettingsCommand command = ProjectSettingsCommand.none,
    Map<String, bool>? gates,
    int? saved,
    bool removed = false,
    String? error,
  }) => ProjectSettingsState(
    projectId: projectId,
    command: command,
    gates: gates ?? this.gates,
    saved: saved ?? this.saved,
    removed: removed,
    error: error,
  );

  @override
  List<Object?> get props => [projectId, command, gates, saved, removed, error];
}

/// Project settings (U6d): the base branch, the gates (D-13) and removing
/// the project. Store ids are edited in the flavor's sheet, the git host is
/// shown as it is.
class ProjectSettingsBloc
    extends Bloc<ProjectSettingsEvent, ProjectSettingsState> {
  new({required this._projects, required this._approvals})
    : super(const ProjectSettingsState()) {
    on<ProjectSettingsStarted>(_onStarted, transformer: restartable());
    on<ProjectBaseBranchSaved>(_onBaseBranch, transformer: droppable());
    on<ProjectGateChanged>(_onGate, transformer: droppable());
    on<ProjectRemoveRequested>(_onRemove, transformer: droppable());
  }

  final ProjectsRepository _projects;
  final ApprovalsRepository _approvals;

  Future<void> _onStarted(
    ProjectSettingsStarted event,
    Emitter<ProjectSettingsState> emit,
  ) async {
    emit(
      ProjectSettingsState(
        projectId: event.projectId,
        command: ProjectSettingsCommand.loading,
      ),
    );
    await _run(emit, () async {
      final gates = await _approvals.getGates(event.projectId);
      return state._with(gates: gates.gates);
    });
  }

  Future<void> _onBaseBranch(
    ProjectBaseBranchSaved event,
    Emitter<ProjectSettingsState> emit,
  ) async {
    emit(state._with(command: ProjectSettingsCommand.saving));
    await _run(emit, () async {
      await _projects.editProject(
        state.projectId,
        ProfileEdits(defaultBaseBranch: event.branch.trim()),
      );
      return state._with(saved: state.saved + 1);
    });
  }

  Future<void> _onGate(
    ProjectGateChanged event,
    Emitter<ProjectSettingsState> emit,
  ) async {
    emit(state._with(command: ProjectSettingsCommand.saving));
    await _run(emit, () async {
      final gates = await _approvals.setGates(
        state.projectId,
        ProjectGates({...?state.gates, event.action: event.on}),
      );
      return state._with(gates: gates.gates);
    });
  }

  Future<void> _onRemove(
    ProjectRemoveRequested event,
    Emitter<ProjectSettingsState> emit,
  ) async {
    emit(state._with(command: ProjectSettingsCommand.removing));
    await _run(emit, () async {
      await _projects.removeProject(state.projectId);
      return state._with(removed: true);
    });
  }

  Future<void> _run(
    Emitter<ProjectSettingsState> emit,
    Future<ProjectSettingsState> Function() request,
  ) async {
    try {
      emit(await request());
    } on Exception catch (error) {
      emit(state._with(error: errorMessage(error)));
    }
  }
}

import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_repositories/xp_repositories.dart';

sealed class ProjectsEvent extends Equatable {
  const new();

  @override
  List<Object?> get props => [];
}

/// Starts following the projects of the engine.
final class ProjectsSubscriptionRequested extends ProjectsEvent {
  const new();
}

/// Scans [projectId] again.
final class ProjectScanRequested extends ProjectsEvent {
  const new(this.projectId);

  final String projectId;

  @override
  List<Object?> get props => [projectId];
}

class ProjectsState extends Equatable {
  const new({
    this.loaded = false,
    this.projects = const [],
    this.cached = false,
    this.scanning,
    this.error,
  });

  /// Whether the projects arrived (from the cache or the engine).
  final bool loaded;
  final List<Project> projects;

  /// Whether [projects] came from the offline cache.
  final bool cached;

  /// The project being scanned again, if any.
  final String? scanning;

  /// What the engine said when the last command failed.
  final String? error;

  Project? byId(String? id) {
    for (final project in projects) {
      if (project.id == id) return project;
    }
    return null;
  }

  @override
  List<Object?> get props => [loaded, projects, cached, scanning, error];
}

/// The projects of the active engine, for the sidebar and the pages that
/// pick one.
class ProjectsBloc extends Bloc<ProjectsEvent, ProjectsState> {
  new({required this._projects}) : super(const ProjectsState()) {
    on<ProjectsSubscriptionRequested>(_onSubscribe, transformer: restartable());
    on<ProjectScanRequested>(_onScan, transformer: droppable());
  }

  final ProjectsRepository _projects;

  Future<void> _onSubscribe(
    ProjectsSubscriptionRequested event,
    Emitter<ProjectsState> emit,
  ) => emit.forEach<Snapshot<List<Project>>>(
    _projects.watchProjects(),
    onData: (snapshot) => ProjectsState(
      loaded: true,
      projects: snapshot.value,
      cached: snapshot.cached,
      scanning: state.scanning,
    ),
    onError: (error, _) => ProjectsState(
      loaded: true,
      projects: state.projects,
      cached: state.cached,
      error: errorMessage(error),
    ),
  );

  Future<void> _onScan(
    ProjectScanRequested event,
    Emitter<ProjectsState> emit,
  ) async {
    emit(_with(scanning: event.projectId));
    try {
      final scanned = await _projects.scanProject(event.projectId);
      emit(
        ProjectsState(
          loaded: true,
          projects: [
            for (final project in state.projects)
              if (project.id == scanned.id) scanned else project,
          ],
          cached: state.cached,
        ),
      );
    } on Exception catch (error) {
      emit(_with(error: errorMessage(error)));
    }
  }

  ProjectsState _with({String? scanning, String? error}) => ProjectsState(
    loaded: state.loaded,
    projects: state.projects,
    cached: state.cached,
    scanning: scanning,
    error: error,
  );
}

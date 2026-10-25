import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_repositories/xp_repositories.dart';

sealed class AddProjectEvent extends Equatable {
  const new();

  @override
  List<Object?> get props => [];
}

/// Adds the repository at [path] and scans it.
final class AddProjectSubmitted extends AddProjectEvent {
  const new(this.path, {this.sshUrl});

  final String path;

  /// The SSH URL the owner confirmed for an HTTPS origin on a host other
  /// than GitHub (ADR 0015).
  final String? sshUrl;

  @override
  List<Object?> get props => [path, sshUrl];
}

/// Scans the added project again.
final class AddProjectRescanned extends AddProjectEvent {
  const new();
}

/// Removes the project that was just added.
final class AddProjectDiscarded extends AddProjectEvent {
  const new();
}

enum AddProjectStatus { idle, adding, review, scanning, discarded, failed }

class AddProjectState extends Equatable {
  const new({
    this.status = AddProjectStatus.idle,
    this.project,
    this.error,
    this.sshUrl,
  });

  final AddProjectStatus status;

  /// The project as the last scan saw it.
  final Project? project;

  /// What the engine said when the last step failed.
  final String? error;

  /// The SSH URL the engine offers for a folder whose origin is an HTTPS URL
  /// on a host other than GitHub, for the owner to confirm (ADR 0015).
  final String? sshUrl;

  @override
  List<Object?> get props => [status, project, error, sshUrl];
}

/// Add project by folder, then the review of its scan: keep it, scan it
/// again after a fix, or remove it.
class AddProjectBloc extends Bloc<AddProjectEvent, AddProjectState> {
  new({required this._projects}) : super(const AddProjectState()) {
    on<AddProjectSubmitted>(_onSubmitted, transformer: droppable());
    on<AddProjectRescanned>(_onRescanned, transformer: droppable());
    on<AddProjectDiscarded>(_onDiscarded, transformer: droppable());
  }

  final ProjectsRepository _projects;

  Future<void> _onSubmitted(
    AddProjectSubmitted event,
    Emitter<AddProjectState> emit,
  ) async {
    emit(const AddProjectState(status: AddProjectStatus.adding));
    try {
      final project = await _projects.addProject(
        event.path.trim(),
        sshUrl: event.sshUrl,
      );
      emit(AddProjectState(status: AddProjectStatus.review, project: project));
    } on SshUrlRequired catch (error) {
      emit(
        AddProjectState(
          status: AddProjectStatus.failed,
          error: error.message,
          sshUrl: error.sshUrl,
        ),
      );
    } on Exception catch (error) {
      emit(
        AddProjectState(
          status: AddProjectStatus.failed,
          error: errorMessage(error),
        ),
      );
    }
  }

  Future<void> _onRescanned(
    AddProjectRescanned event,
    Emitter<AddProjectState> emit,
  ) async {
    final project = state.project;
    if (project == null) return;
    emit(AddProjectState(status: AddProjectStatus.scanning, project: project));
    try {
      final scanned = await _projects.scanProject(project.id);
      emit(AddProjectState(status: AddProjectStatus.review, project: scanned));
    } on Exception catch (error) {
      emit(
        AddProjectState(
          status: AddProjectStatus.review,
          project: project,
          error: errorMessage(error),
        ),
      );
    }
  }

  Future<void> _onDiscarded(
    AddProjectDiscarded event,
    Emitter<AddProjectState> emit,
  ) async {
    final project = state.project;
    if (project == null) return;
    try {
      await _projects.removeProject(project.id);
      emit(const AddProjectState(status: AddProjectStatus.discarded));
    } on Exception catch (error) {
      emit(
        AddProjectState(
          status: AddProjectStatus.review,
          project: project,
          error: errorMessage(error),
        ),
      );
    }
  }
}

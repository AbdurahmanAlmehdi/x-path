import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';

/// What the content area of the shell shows.
sealed class ShellDestination extends Equatable {
  const new();

  @override
  List<Object?> get props => [];
}

/// The first project, or the empty state.
final class HomeDestination extends ShellDestination {
  const new();
}

/// One project.
final class ProjectDestination extends ShellDestination {
  const new(this.projectId);

  final String projectId;

  @override
  List<Object?> get props => [projectId];
}

/// The job view of the run [runId], showing [jobId] first if given.
/// [projectId] keeps the project selected in the sidebar.
final class JobDestination extends ShellDestination {
  const new(this.runId, {this.jobId, this.projectId});

  final String runId;
  final String? jobId;
  final String? projectId;

  @override
  List<Object?> get props => [runId, jobId, projectId];
}

/// Add project.
final class AddProjectDestination extends ShellDestination {
  const new();
}

/// The credentials, of [projectId] if given (else the first project).
final class CredentialsDestination extends ShellDestination {
  const new([this.projectId]);

  final String? projectId;

  @override
  List<Object?> get props => [projectId];
}

/// The engine list.
final class EnginesDestination extends ShellDestination {
  const new();
}

/// Setting up this Mac (onboarding inside the window).
final class OnboardingDestination extends ShellDestination {
  const new();
}

/// Where the shell is. It lives inside the engine's subtree, so switching
/// engines starts over at [HomeDestination].
class ShellCubit extends Cubit<ShellDestination> {
  new([super.initialState = const HomeDestination()]);

  void show(ShellDestination destination) => emit(destination);
}

import 'dart:async';

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

/// The releases of [projectId], showing [releaseId] first if given.
final class ReleasesDestination extends ShellDestination {
  const new(this.projectId, {this.releaseId});

  final String projectId;
  final String? releaseId;

  @override
  List<Object?> get props => [projectId, releaseId];
}

/// The tests of [projectId], showing the run of [jobId] if given, else the
/// latest.
final class TestsDestination extends ShellDestination {
  const new(this.projectId, {this.jobId});

  final String projectId;
  final String? jobId;

  @override
  List<Object?> get props => [projectId, jobId];
}

/// The runs of [projectId], newest first.
final class RunsDestination extends ShellDestination {
  const new(this.projectId);

  final String projectId;

  @override
  List<Object?> get props => [projectId];
}

/// The workflows of [projectId] in the builder, showing [workflowId] first
/// if given.
final class WorkflowsDestination extends ShellDestination {
  const new(this.projectId, {this.workflowId});

  final String projectId;
  final String? workflowId;

  @override
  List<Object?> get props => [projectId, workflowId];
}

/// The runners of the engine.
final class RunnersDestination extends ShellDestination {
  const new();
}

/// What the engine keeps on its disk.
final class StorageDestination extends ShellDestination {
  const new();
}

/// The approvals inbox, showing [approvalId] first if given.
final class ApprovalsDestination extends ShellDestination {
  const new({this.approvalId});

  final String? approvalId;

  @override
  List<Object?> get props => [approvalId];
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

/// The settings: the versions, the engine's GitHub token and "Remove
/// XPath". [github] puts the cursor in the GitHub token field.
final class SettingsDestination extends ShellDestination {
  const new({this.github = false});

  final bool github;

  @override
  List<Object?> get props => [github];
}

/// Whether the shown destination may be left; `false` keeps it (the owner
/// chose to keep a draft).
typedef CanLeave = Future<bool> Function();

/// Where the shell is. It lives inside the engine's subtree, so switching
/// engines starts over at [HomeDestination].
class ShellCubit extends Cubit<ShellDestination> {
  new([super.initialState = const HomeDestination()]);

  CanLeave? _canLeave;

  /// Shows [destination], once the guard of the shown one (if any) lets it
  /// go.
  void show(ShellDestination destination) {
    final canLeave = _canLeave;
    if (canLeave == null || destination == state) {
      emit(destination);
      return;
    }
    unawaited(_leave(canLeave, destination));
  }

  Future<void> _leave(CanLeave canLeave, ShellDestination destination) async {
    if (await canLeave() && !isClosed) emit(destination);
  }

  /// Asks [canLeave] before every later [show] that leaves the shown
  /// destination (the builder with a draft). Returns what lets it go again.
  void Function() guard(CanLeave canLeave) {
    _canLeave = canLeave;
    return () {
      if (identical(_canLeave, canLeave)) _canLeave = null;
    };
  }

  /// The project the destination shows, if it shows one.
  String? get projectId => switch (state) {
    ProjectDestination(:final projectId) ||
    ReleasesDestination(:final projectId) ||
    TestsDestination(:final projectId) ||
    WorkflowsDestination(:final projectId) => projectId,
    JobDestination(:final projectId) => projectId,
    _ => null,
  };
}

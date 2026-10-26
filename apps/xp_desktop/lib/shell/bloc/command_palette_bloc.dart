import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/shell/cubit/shell_cubit.dart';
import 'package:xp_repositories/xp_repositories.dart';

/// One row of the command palette (⌘K): a place to go or a command to run.
sealed class PaletteEntry extends Equatable {
  const new();

  /// Where choosing it goes, for an entry that goes somewhere.
  ShellDestination? get destination => null;
}

/// A project.
final class GoToProject extends PaletteEntry {
  const new(this.project);

  final Project project;

  @override
  ShellDestination get destination => ProjectDestination(project.id);

  @override
  List<Object?> get props => [project];
}

/// A release, on the releases page of its project.
final class GoToRelease extends PaletteEntry {
  const new(this.release);

  final Release release;

  @override
  ShellDestination get destination =>
      ReleasesDestination(release.projectId, releaseId: release.id);

  @override
  List<Object?> get props => [release];
}

/// A run of the shown project, with the title of its workflow.
final class GoToRun extends PaletteEntry {
  const new(this.run, {this.workflow});

  final Run run;
  final String? workflow;

  @override
  ShellDestination get destination =>
      JobDestination(run.id, projectId: run.projectId);

  @override
  List<Object?> get props => [run, workflow];
}

/// A workflow of the shown project, in the builder.
final class GoToWorkflow extends PaletteEntry {
  const new(this.workflow);

  final WorkflowSummary workflow;

  @override
  ShellDestination get destination =>
      WorkflowsDestination(workflow.projectId, workflowId: workflow.id);

  @override
  List<Object?> get props => [workflow];
}

/// A page: approvals, runners, credentials, storage, engines, settings, and
/// the releases, runs, tests and workflows of the shown project.
final class GoToPage extends PaletteEntry {
  const new(this.page);

  final ShellDestination page;

  @override
  ShellDestination get destination => page;

  @override
  List<Object?> get props => [page];
}

/// Dispatch… for a project.
final class DispatchEntry extends PaletteEntry {
  const new(this.project);

  final Project project;

  @override
  List<Object?> get props => [project];
}

/// Run again: the newest finished run of the shown project.
final class RunAgainEntry extends PaletteEntry {
  const new(this.run, {this.workflow});

  final Run run;
  final String? workflow;

  @override
  List<Object?> get props => [run, workflow];
}

/// Cancel a run of the shown project that has not finished.
final class CancelEntry extends PaletteEntry {
  const new(this.run, {this.workflow});

  final Run run;
  final String? workflow;

  @override
  List<Object?> get props => [run, workflow];
}

/// Review a pending approval. Approving still opens the review sheet, with
/// its delay (D-13); the palette never approves on its own.
final class ApproveEntry extends PaletteEntry {
  const new(this.approval);

  final Approval approval;

  @override
  List<Object?> get props => [approval];
}

sealed class CommandPaletteEvent extends Equatable {
  const new();
}

/// The palette opens over [projectId], the project the shell shows, if
/// any: reads what it can go to and run.
final class CommandPaletteOpened extends CommandPaletteEvent {
  const new({this.projectId});

  final String? projectId;

  @override
  List<Object?> get props => [projectId];
}

/// The owner typed [query].
final class CommandPaletteQueryChanged extends CommandPaletteEvent {
  const new(this.query);

  final String query;

  @override
  List<Object?> get props => [query];
}

/// Runs the workflow of [run] again, as it was dispatched.
final class CommandPaletteRunAgainRequested extends CommandPaletteEvent {
  const new(this.run);

  final Run run;

  @override
  List<Object?> get props => [run];
}

/// Cancels the jobs of [run] that have not ended; the owner confirmed it.
final class CommandPaletteCancelRequested extends CommandPaletteEvent {
  const new(this.run);

  final Run run;

  @override
  List<Object?> get props => [run];
}

class CommandPaletteState extends Equatable {
  const new({
    this.loading = false,
    this.entries = const [],
    this.query = '',
    this.done = 0,
    this.startedRun,
    this.error,
  });

  /// Whether the entries are being read.
  final bool loading;

  /// Every entry, commands first.
  final List<PaletteEntry> entries;

  /// What the owner typed.
  final String query;

  /// How many commands of the palette (run again, cancel) ended; it grows
  /// with each, so the same result twice is told twice.
  final int done;

  /// The run the last "Run again" started.
  final Run? startedRun;

  /// What the engine said when the last command failed.
  final String? error;

  /// The entries whose [labelOf] has every word of [query], in any order.
  List<PaletteEntry> matches(String Function(PaletteEntry entry) labelOf) {
    final words = query.toLowerCase().split(' ').where((w) => w.isNotEmpty);
    return [
      for (final entry in entries)
        if (words.every(labelOf(entry).toLowerCase().contains)) entry,
    ];
  }

  CommandPaletteState copyWith({
    bool? loading,
    List<PaletteEntry>? entries,
    String? query,
  }) => CommandPaletteState(
    loading: loading ?? this.loading,
    entries: entries ?? this.entries,
    query: query ?? this.query,
    done: done,
    startedRun: startedRun,
    error: error,
  );

  /// This state after a command ended, with the run it started or the
  /// [error] it failed with.
  CommandPaletteState _ended({Run? startedRun, String? error}) =>
      CommandPaletteState(
        loading: loading,
        entries: entries,
        query: query,
        done: done + 1,
        startedRun: startedRun,
        error: error,
      );

  @override
  List<Object?> get props => [loading, entries, query, done, startedRun, error];
}

/// The command palette (⌘K): go to a project, release, run, workflow or
/// page; dispatch, run again, cancel, review an approval. It reads the
/// engine each time it opens; what cannot be read is left out.
class CommandPaletteBloc
    extends Bloc<CommandPaletteEvent, CommandPaletteState> {
  new({
    required this._projects,
    required this._releases,
    required this._jobs,
    required this._workflows,
    required this._approvals,
  }) : super(const CommandPaletteState()) {
    on<CommandPaletteOpened>(_onOpened, transformer: restartable());
    on<CommandPaletteQueryChanged>(
      (event, emit) => emit(state.copyWith(query: event.query)),
    );
    on<CommandPaletteRunAgainRequested>(
      (event, emit) => _command(emit, () => _jobs.runAgain(event.run.id)),
      transformer: droppable(),
    );
    on<CommandPaletteCancelRequested>(
      (event, emit) => _command(emit, () async {
        await _jobs.cancelRun(event.run.id);
        return null;
      }),
      transformer: droppable(),
    );
  }

  /// Sends a command to the engine, and tells how it ended.
  Future<void> _command(
    Emitter<CommandPaletteState> emit,
    Future<Run?> Function() send,
  ) async {
    try {
      emit(state._ended(startedRun: await send()));
    } on Exception catch (error) {
      emit(state._ended(error: errorMessage(error)));
    }
  }

  final ProjectsRepository _projects;
  final ReleasesRepository _releases;
  final JobsRepository _jobs;
  final WorkflowsRepository _workflows;
  final ApprovalsRepository _approvals;

  /// The most releases and runs listed.
  static const limit = 10;

  Future<void> _onOpened(
    CommandPaletteOpened event,
    Emitter<CommandPaletteState> emit,
  ) async {
    emit(const CommandPaletteState(loading: true));
    final projectId = event.projectId;
    final projects = await _read(() => _first(_projects.watchProjects()));
    final shown = projects.where((project) => project.id == projectId);
    final workflows = projectId == null
        ? const <WorkflowSummary>[]
        : await _read(() => _workflows.listWorkflows(projectId));
    final titles = {
      for (final workflow in workflows)
        workflow.id: workflow.title ?? workflow.name,
    };
    final runs = projectId == null
        ? const <Run>[]
        : await _read(
            () async => [
              ...?(await _firstOf(_jobs.watchRuns(projectId, limit: limit)))
                  ?.runs,
            ],
          );
    final releases = await _read(() => _first(_releases.watchReleases()));
    final approvals = await _read(
      () => _first(_approvals.watchApprovals(state: ApprovalState.pending)),
    );
    final finished = runs.where((run) => run.state.isFinished).firstOrNull;
    emit(
      CommandPaletteState(
        query: state.query,
        entries: [
          for (final project in shown) DispatchEntry(project),
          for (final approval in approvals) ApproveEntry(approval),
          for (final run in runs)
            if (!run.state.isFinished)
              CancelEntry(run, workflow: titles[run.workflowId]),
          if (finished != null)
            RunAgainEntry(finished, workflow: titles[finished.workflowId]),
          for (final project in projects) GoToProject(project),
          if (projectId != null) ...[
            GoToPage(ReleasesDestination(projectId)),
            GoToPage(RunsDestination(projectId)),
            GoToPage(TestsDestination(projectId)),
            GoToPage(WorkflowsDestination(projectId)),
          ],
          for (final run in runs)
            GoToRun(run, workflow: titles[run.workflowId]),
          for (final workflow in workflows)
            if (!workflow.archived) GoToWorkflow(workflow),
          for (final release in releases.take(limit)) GoToRelease(release),
          const GoToPage(ApprovalsDestination()),
          const GoToPage(RunnersDestination()),
          GoToPage(CredentialsDestination(projectId)),
          const GoToPage(StorageDestination()),
          const GoToPage(EnginesDestination()),
          const GoToPage(SettingsDestination()),
        ],
      ),
    );
  }

  /// The first value of [snapshots], or `null` if it ends without one.
  static Future<T?> _firstOf<T>(Stream<Snapshot<T>> snapshots) => snapshots
      .map<T?>((snapshot) => snapshot.value)
      .firstWhere((_) => true, orElse: () => null);

  static Future<List<T>> _first<T>(Stream<Snapshot<List<T>>> snapshots) async =>
      await _firstOf(snapshots) ?? const [];

  static Future<List<T>> _read<T>(Future<List<T>> Function() read) async {
    try {
      return await read();
    } on Exception {
      return const [];
    }
  }
}

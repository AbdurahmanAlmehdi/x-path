import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_repositories/xp_repositories.dart';

sealed class ProjectOverviewEvent extends Equatable {
  const new();

  @override
  List<Object?> get props => [];
}

/// Starts following the releases and credentials of [projectId].
final class ProjectOverviewSubscriptionRequested extends ProjectOverviewEvent {
  const new(this.projectId);

  final String projectId;

  @override
  List<Object?> get props => [projectId];
}

/// Shows the ledger rows of [flavor] only, or every row when `null`.
final class ProjectOverviewFilterChanged extends ProjectOverviewEvent {
  const new(this.flavor);

  final String? flavor;

  @override
  List<Object?> get props => [flavor];
}

/// Follows the run of the release in flight.
final class _HeroRunRequested extends ProjectOverviewEvent {
  const new(this.runId);

  final String? runId;
}

/// Reads the workflow of the hero run, for the names of its stages.
final class _HeroWorkflowRequested extends ProjectOverviewEvent {
  const new(this.run);

  final Run run;
}

/// The release states between dispatch and the stores' verdict: a release
/// in one of them is "in flight" and is the overview's hero.
const Set<ReleaseState> inFlightStates = {
  ReleaseState.draft,
  ReleaseState.building,
  ReleaseState.uploaded,
  ReleaseState.inReview,
  ReleaseState.rejected,
  ReleaseState.approved,
};

class ProjectOverviewState extends Equatable {
  const new({
    this.loaded = false,
    this.releases = const [],
    this.credentials = const [],
    this.cached = false,
    this.heroRun,
    this.heroOutline,
    this.runners = const {},
    this.filter,
    this.error,
  });

  /// Whether the releases arrived (from the cache or the engine).
  final bool loaded;

  /// The releases of the project, newest first.
  final List<Release> releases;

  /// The credentials of the project.
  final List<Credential> credentials;

  /// Whether [releases] came from the offline cache.
  final bool cached;

  /// The run of the current build of [heroRelease], with its jobs.
  final RunJobs? heroRun;

  /// The workflow [heroRun] runs, for the names of its stages.
  final WorkflowOutline? heroOutline;

  /// The name of each runner, by id.
  final Map<String, String> runners;

  /// The flavor the ledger shows, or `null` for all.
  final String? filter;

  /// What the engine said when it could not be read.
  final String? error;

  /// The name of stage [index] of [heroRun], if its workflow has one.
  String? heroStageName(int index) {
    final stages = heroOutline?.stages;
    if (stages == null || index >= stages.length) return null;
    final name = stages[index].name;
    return name.isEmpty ? null : name;
  }

  /// The newest release in flight, if any.
  Release? get heroRelease {
    for (final release in releases) {
      if (inFlightStates.contains(release.state)) return release;
    }
    return null;
  }

  ProjectOverviewState copyWith({
    bool? loaded,
    List<Release>? releases,
    List<Credential>? credentials,
    bool? cached,
    RunJobs? Function()? heroRun,
    WorkflowOutline? Function()? heroOutline,
    Map<String, String>? runners,
    String? Function()? filter,
    String? Function()? error,
  }) => ProjectOverviewState(
    loaded: loaded ?? this.loaded,
    releases: releases ?? this.releases,
    credentials: credentials ?? this.credentials,
    cached: cached ?? this.cached,
    heroRun: heroRun == null ? this.heroRun : heroRun(),
    heroOutline: heroOutline == null ? this.heroOutline : heroOutline(),
    runners: runners ?? this.runners,
    filter: filter == null ? this.filter : filter(),
    error: error == null ? this.error : error(),
  );

  @override
  List<Object?> get props => [
    loaded,
    releases,
    credentials,
    cached,
    heroRun,
    heroOutline,
    runners,
    filter,
    error,
  ];
}

/// The project overview (1A): the release in flight with the run that builds
/// it, and the releases and credentials behind the flavor ledger.
class ProjectOverviewBloc
    extends Bloc<ProjectOverviewEvent, ProjectOverviewState> {
  new({
    required this._releases,
    required this._projects,
    required this._jobs,
    required this._workflows,
    required this._runners,
  }) : super(const ProjectOverviewState()) {
    on<ProjectOverviewSubscriptionRequested>(
      _onSubscribe,
      transformer: restartable(),
    );
    on<_HeroRunRequested>(_onHeroRun, transformer: restartable());
    on<_HeroWorkflowRequested>(_onHeroWorkflow, transformer: restartable());
    on<ProjectOverviewFilterChanged>(
      (event, emit) => emit(state.copyWith(filter: () => event.flavor)),
    );
  }

  final ReleasesRepository _releases;
  final ProjectsRepository _projects;
  final JobsRepository _jobs;
  final WorkflowsRepository _workflows;
  final RunnersRepository _runners;
  String? _heroRunId;

  Future<void> _onSubscribe(
    ProjectOverviewSubscriptionRequested event,
    Emitter<ProjectOverviewState> emit,
  ) async {
    final releases = emit.forEach<Snapshot<List<Release>>>(
      _releases.watchReleases(projectId: event.projectId),
      onData: (snapshot) {
        final next = state.copyWith(
          loaded: true,
          releases: snapshot.value,
          cached: snapshot.cached,
          error: () => null,
        );
        final runId = next.heroRelease?.builds.lastOrNull?.runId;
        if (runId != _heroRunId) {
          _heroRunId = runId;
          add(_HeroRunRequested(runId));
        }
        return next;
      },
      onError: (error, _) =>
          state.copyWith(loaded: true, error: () => errorMessage(error)),
    );
    final credentials = emit.forEach<Snapshot<List<Credential>>>(
      _projects.watchCredentials(event.projectId),
      onData: (snapshot) => state.copyWith(credentials: snapshot.value),
      onError: (_, _) => state,
    );
    final runners = emit.forEach<Snapshot<List<Runner>>>(
      _runners.watchRunners(),
      onData: (snapshot) => state.copyWith(
        runners: {for (final runner in snapshot.value) runner.id: runner.name},
      ),
      onError: (_, _) => state,
    );
    await Future.wait([releases, credentials, runners]);
  }

  Future<void> _onHeroRun(
    _HeroRunRequested event,
    Emitter<ProjectOverviewState> emit,
  ) async {
    final runId = event.runId;
    emit(state.copyWith(heroRun: () => null, heroOutline: () => null));
    if (runId == null) return;
    var asked = false;
    await emit.forEach<Snapshot<RunJobs>>(
      _jobs.watchRunJobs(runId),
      onData: (snapshot) {
        if (!asked) {
          asked = true;
          add(_HeroWorkflowRequested(snapshot.value.run));
        }
        return state.copyWith(heroRun: () => snapshot.value);
      },
      onError: (_, _) => state,
    );
  }

  Future<void> _onHeroWorkflow(
    _HeroWorkflowRequested event,
    Emitter<ProjectOverviewState> emit,
  ) async {
    try {
      final workflow = await _workflows.workflowOf(event.run);
      emit(
        state.copyWith(heroOutline: () => WorkflowOutline.parse(workflow.yaml)),
      );
    } on Exception {
      // The stages keep their numbers.
    }
  }
}

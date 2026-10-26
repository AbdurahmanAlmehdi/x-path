import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/credentials/flavor_target.dart';
import 'package:xp_repositories/xp_repositories.dart';

sealed class SetupChecklistEvent extends Equatable {
  const new();
}

/// Reads where the setup of [project] stands, or of the engine alone when
/// it has no project yet, and follows it.
final class SetupChecklistStarted extends SetupChecklistEvent {
  const new(this.project);

  final Project? project;

  @override
  List<Object?> get props => [project];
}

/// The steps from a new engine to a first green build (U5a), in order.
enum SetupStepKind {
  /// The engine runs and the app is connected to it: always done here.
  engine,

  /// The engine has a GitHub token. For GitHub projects only.
  gitHub,

  /// The engine has a project.
  project,

  /// Every flavor has a credential.
  credentials,

  /// Every flavor has the store ids its uploads need (U2a).
  storeIds,

  /// A runner (the engine's own or a remote one) can run the builds. Only
  /// listed when one cannot.
  runners,

  /// The project has a run.
  firstBuild,
}

/// One step of the checklist.
class SetupStep extends Equatable {
  const new(this.kind, {required this.done, this.target, this.reasons});

  final SetupStepKind kind;
  final bool done;

  /// The first flavor still missing what [kind] needs, for
  /// [SetupStepKind.credentials] and [SetupStepKind.storeIds].
  final FlavorTarget? target;

  /// Why no runner can run a build, for [SetupStepKind.runners].
  final List<String>? reasons;

  @override
  List<Object?> get props => [kind, done, target, reasons];
}

class SetupChecklistState extends Equatable {
  const new({
    this.loaded = false,
    this.project,
    this.gitHubConnected = false,
    this.credentials = const [],
    this.hasRun = false,
    this.hasRelease,
    this.waitReasons = const [],
    this.smokeWorkflowId,
  });

  /// Whether what the steps need has arrived.
  final bool loaded;

  final Project? project;

  /// Whether the engine has a GitHub token GitHub accepts.
  final bool gitHubConnected;

  /// The credentials of [project].
  final List<Credential> credentials;

  /// Whether [project] has a run.
  final bool hasRun;

  /// Whether [project] has a release: its owner is past the first run.
  /// `null` until the releases arrive.
  final bool? hasRelease;

  /// Why the jobs of a dev build would wait for a runner, from the engine's
  /// dry run (UX-01); empty when a runner can run them all.
  final List<String> waitReasons;

  /// The built-in `smoke-build` of [project], for "Try an unsigned build".
  final String? smokeWorkflowId;

  /// The steps, in order. The GitHub step is for GitHub projects (and for
  /// an engine with no project yet), never for one on another host.
  List<SetupStep> get steps {
    final project = this.project;
    final withoutCredentials = project == null
        ? null
        : _withoutCredentials(project);
    final withoutStoreIds = project == null ? null : _withoutStoreIds(project);
    return [
      const SetupStep(SetupStepKind.engine, done: true),
      if (project == null || project.isOnGitHub)
        SetupStep(SetupStepKind.gitHub, done: gitHubConnected),
      SetupStep(SetupStepKind.project, done: project != null),
      SetupStep(
        SetupStepKind.credentials,
        done: project != null && withoutCredentials == null,
        target: withoutCredentials,
      ),
      SetupStep(
        SetupStepKind.storeIds,
        done: project != null && withoutStoreIds == null,
        target: withoutStoreIds,
      ),
      if (waitReasons.isNotEmpty)
        SetupStep(SetupStepKind.runners, done: false, reasons: waitReasons),
      SetupStep(SetupStepKind.firstBuild, done: hasRun),
    ];
  }

  /// Whether the checklist shows: once what it needs has arrived (the
  /// releases of a project too, so it never flashes on one that has them),
  /// until every step is done or the project has a release.
  bool get visible =>
      loaded &&
      (project == null || hasRelease == false) &&
      steps.any((step) => !step.done);

  /// How many steps are done.
  int get doneCount => steps.where((step) => step.done).length;

  FlavorTarget? _withoutCredentials(Project project) => _firstFlavor(
    project,
    (app, flavor) => !credentials.any(
      (credential) =>
          credential.app == app.path && credential.flavor == flavor.name,
    ),
  );

  static FlavorTarget? _withoutStoreIds(Project project) => _firstFlavor(
    project,
    (app, flavor) =>
        (app.hasAndroid && flavor.firebaseAppId?['android'] == null) ||
        (app.hasIos && flavor.appleAppId == null),
  );

  static FlavorTarget? _firstFlavor(
    Project project,
    bool Function(AppProfile app, FlavorProfile flavor) missing,
  ) {
    for (final app in project.profile.apps) {
      for (final flavor in app.flavors) {
        if (missing(app, flavor)) {
          return (app: app.path, appName: app.name, flavor: flavor.name);
        }
      }
    }
    return null;
  }

  SetupChecklistState copyWith({
    bool? loaded,
    bool? gitHubConnected,
    List<Credential>? credentials,
    bool? hasRun,
    bool? hasRelease,
    List<String>? waitReasons,
    String? smokeWorkflowId,
  }) => SetupChecklistState(
    loaded: loaded ?? this.loaded,
    project: project,
    gitHubConnected: gitHubConnected ?? this.gitHubConnected,
    credentials: credentials ?? this.credentials,
    hasRun: hasRun ?? this.hasRun,
    hasRelease: hasRelease ?? this.hasRelease,
    waitReasons: waitReasons ?? this.waitReasons,
    smokeWorkflowId: smokeWorkflowId ?? this.smokeWorkflowId,
  );

  @override
  List<Object?> get props => [
    loaded,
    project,
    gitHubConnected,
    credentials,
    hasRun,
    hasRelease,
    waitReasons,
    smokeWorkflowId,
  ];
}

/// The setup checklist of NoProjects and the overview (U5a): engine, GitHub,
/// project, credentials, store ids, runners and a first build, each read
/// from the engine.
class SetupChecklistBloc
    extends Bloc<SetupChecklistEvent, SetupChecklistState> {
  new({
    required this._settings,
    required this._projects,
    required this._jobs,
    required this._releases,
    required this._workflows,
  }) : super(const SetupChecklistState()) {
    on<SetupChecklistStarted>(_onStarted, transformer: restartable());
  }

  final SettingsRepository _settings;
  final ProjectsRepository _projects;
  final JobsRepository _jobs;
  final ReleasesRepository _releases;
  final WorkflowsRepository _workflows;

  Future<void> _onStarted(
    SetupChecklistStarted event,
    Emitter<SetupChecklistState> emit,
  ) async {
    final project = event.project;
    emit(SetupChecklistState(project: project));
    final gitHub = await _gitHubConnected();
    if (project == null) {
      emit(state.copyWith(loaded: true, gitHubConnected: gitHub));
      return;
    }
    final (smoke, reasons) = await _builds(project.id);
    emit(
      state.copyWith(
        loaded: true,
        gitHubConnected: gitHub,
        smokeWorkflowId: smoke,
        waitReasons: reasons,
      ),
    );
    await Future.wait([
      emit.forEach<Snapshot<List<Credential>>>(
        _projects.watchCredentials(project.id),
        onData: (snapshot) => state.copyWith(credentials: snapshot.value),
        onError: (_, _) => state,
      ),
      emit.forEach<Snapshot<RunsResponse>>(
        _jobs.watchRuns(project.id, limit: 1),
        onData: (snapshot) =>
            state.copyWith(hasRun: snapshot.value.runs.isNotEmpty),
        onError: (_, _) => state,
      ),
      emit.forEach<Snapshot<List<Release>>>(
        _releases.watchReleases(projectId: project.id),
        onData: (snapshot) =>
            state.copyWith(hasRelease: snapshot.value.isNotEmpty),
        onError: (_, _) => state,
      ),
    ]);
  }

  Future<bool> _gitHubConnected() async {
    try {
      final token = await _settings.gitHubToken();
      return token.stored && token.status == CredentialStatus.verified;
    } on Exception {
      return false;
    }
  }

  /// The built-in smoke build of [projectId], and why the jobs of its dev
  /// build would wait for a runner, from the engine's dry run.
  Future<(String?, List<String>)> _builds(String projectId) async {
    try {
      final workflows = await _workflows.listWorkflows(projectId);
      String? idOf(String name) => workflows
          .where((workflow) => workflow.builtin && workflow.name == name)
          .firstOrNull
          ?.id;
      final devBuild = idOf('dev-build');
      final plan = devBuild == null
          ? null
          : await _workflows.plan(projectId, devBuild, const DispatchRequest());
      return (
        idOf('smoke-build'),
        {
          for (final stage in plan?.stages ?? const <PlannedStage>[])
            for (final job in stage.jobs) ?job.waitReason,
        }.toList(),
      );
    } on Exception {
      return (null, const <String>[]);
    }
  }
}

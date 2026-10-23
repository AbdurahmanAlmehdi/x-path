import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_repositories/xp_repositories.dart';

sealed class DispatchEvent extends Equatable {
  const new();

  @override
  List<Object?> get props => [];
}

/// Loads the workflows of the project and previews the first.
final class DispatchStarted extends DispatchEvent {
  const new();
}

final class DispatchWorkflowChanged extends DispatchEvent {
  const new(this.workflowId);

  final String workflowId;

  @override
  List<Object?> get props => [workflowId];
}

final class DispatchAppChanged extends DispatchEvent {
  const new(this.app);

  /// The app's path.
  final String app;

  @override
  List<Object?> get props => [app];
}

final class DispatchFlavorToggled extends DispatchEvent {
  const new(this.flavor);

  final String flavor;

  @override
  List<Object?> get props => [flavor];
}

final class DispatchPlatformToggled extends DispatchEvent {
  const new(this.platform);

  final String platform;

  @override
  List<Object?> get props => [platform];
}

final class DispatchRefChanged extends DispatchEvent {
  const new(this.ref);

  final String ref;

  @override
  List<Object?> get props => [ref];
}

final class DispatchRefKindChanged extends DispatchEvent {
  const new(this.kind);

  final RefKind kind;

  @override
  List<Object?> get props => [kind];
}

final class DispatchBumpChanged extends DispatchEvent {
  const new(this.bump);

  final VersionBump bump;

  @override
  List<Object?> get props => [bump];
}

/// The owner set the input [name] to [value]; [valid] is false while the
/// text of a JSON input does not parse.
final class DispatchInputChanged extends DispatchEvent {
  const new(this.name, this.value, {this.valid = true});

  final String name;
  final Object? value;
  final bool valid;

  @override
  List<Object?> get props => [name, value, valid];
}

/// The owner typed the version `x.y.z` to release, instead of a bump.
final class DispatchVersionChanged extends DispatchEvent {
  const new(this.version);

  final String version;

  @override
  List<Object?> get props => [version];
}

/// Dispatches the run the sheet previews.
final class DispatchSubmitted extends DispatchEvent {
  const new();
}

final class _DispatchPreviewRequested extends DispatchEvent {
  const new();
}

/// Whether the ref is a branch or a tag. Both are sent as `ref`; the
/// choice only says what the field holds.
enum RefKind { branch, tag }

enum DispatchStatus { loading, ready, submitting, dispatched }

class DispatchState extends Equatable {
  const new({
    required this.project,
    required this.app,
    required this.ref,
    this.status = DispatchStatus.loading,
    this.workflows = const [],
    this.workflow,
    this.outline,
    this.flavors,
    this.platforms,
    this.refKind = RefKind.branch,
    this.bump = VersionBump.keep,
    this.version = '',
    this.inputs = const {},
    this.invalidInputs = const {},
    this.releases,
    this.preview,
    this.previewing = false,
    this.run,
    this.error,
  });

  final Project project;

  /// The path of the app to run for.
  final String app;
  final DispatchStatus status;

  /// The workflows of the project.
  final List<WorkflowSummary> workflows;

  /// The workflow chosen, as the engine has it now.
  final Workflow? workflow;
  final WorkflowOutline? outline;

  /// The flavors picked, or `null` for the ones the engine takes by default.
  final List<String>? flavors;

  /// The platforms picked, or `null` for every platform the app has.
  final List<String>? platforms;
  final String ref;
  final RefKind refKind;
  final VersionBump bump;

  /// The version `x.y.z` typed instead of a bump; empty for the bump.
  final String version;

  /// The values of the workflow's inputs: the last dispatch's, then what the
  /// owner set. An input that is not here takes its default.
  final Map<String, Object?> inputs;

  /// The JSON inputs whose text does not parse.
  final Set<String> invalidInputs;

  /// The releases of the project, for a release input; `null` until they
  /// arrive or when the workflow has none.
  final List<Release>? releases;

  /// What the dispatch would start.
  final DispatchPreview? preview;

  /// Whether the preview is being worked out again.
  final bool previewing;

  /// The run dispatched.
  final Run? run;

  /// What went wrong last.
  final String? error;

  /// Whether the workflow writes a version, so the bump matters.
  bool get bumps =>
      outline?.stages.any(
        (stage) => stage.jobs.any(
          (job) => job.steps.any((step) => step.kind == 'version.bump'),
        ),
      ) ??
      false;

  /// The flavors the run is for: the ones picked, else the default.
  List<String> get chosenFlavors => flavors ?? preview?.flavors ?? const [];

  /// The platforms the run is for: the ones picked, else the default.
  List<String> get chosenPlatforms =>
      platforms ?? preview?.platforms ?? const [];

  /// The release input of the workflow, if it has one.
  WorkflowInput? get releaseInput => workflow?.inputs
      .where((input) => input.type == InputType.release)
      .firstOrNull;

  /// Whether the workflow takes a release and the project has none yet.
  bool get noReleases =>
      releaseInput != null && releases != null && releases!.isEmpty;

  /// The values the dispatch sends: those of declared inputs that are set,
  /// and the first option of a choice without a default, which the sheet
  /// shows as chosen.
  Map<String, Object?> get _givenInputs => {
    for (final input in workflow?.inputs ?? const <WorkflowInput>[])
      input.name:
          ?(inputs[input.name] ??
          (input.type == InputType.choice && input.defaultValue == null
              ? input.options?.firstOrNull
              : null)),
  };

  /// The body of the dispatch.
  DispatchRequest get request {
    final release = releaseInput;
    final typed = version.trim();
    return DispatchRequest(
      app: app,
      ref: ref.trim().isEmpty ? null : ref.trim(),
      flavors: flavors,
      platforms: platforms,
      bump: bumps && typed.isEmpty ? bump : null,
      version: bumps && typed.isNotEmpty ? typed : null,
      releaseVersion: release == null ? null : inputs[release.name] as String?,
      inputs: _givenInputs,
    );
  }

  /// Whether the sheet can dispatch now.
  bool get canDispatch =>
      status == DispatchStatus.ready &&
      !previewing &&
      workflow != null &&
      invalidInputs.isEmpty &&
      !noReleases &&
      (preview?.jobCount ?? 0) > 0;

  DispatchState copyWith({
    String? app,
    DispatchStatus? status,
    List<WorkflowSummary>? workflows,
    Workflow? workflow,
    WorkflowOutline? outline,
    List<String>? Function()? flavors,
    List<String>? Function()? platforms,
    String? ref,
    RefKind? refKind,
    VersionBump? bump,
    String? version,
    Map<String, Object?>? inputs,
    Set<String>? invalidInputs,
    List<Release>? Function()? releases,
    DispatchPreview? preview,
    bool? previewing,
    Run? run,
    String? Function()? error,
  }) => DispatchState(
    project: project,
    app: app ?? this.app,
    status: status ?? this.status,
    workflows: workflows ?? this.workflows,
    workflow: workflow ?? this.workflow,
    outline: outline ?? this.outline,
    flavors: flavors == null ? this.flavors : flavors(),
    platforms: platforms == null ? this.platforms : platforms(),
    ref: ref ?? this.ref,
    refKind: refKind ?? this.refKind,
    bump: bump ?? this.bump,
    version: version ?? this.version,
    inputs: inputs ?? this.inputs,
    invalidInputs: invalidInputs ?? this.invalidInputs,
    releases: releases == null ? this.releases : releases(),
    preview: preview ?? this.preview,
    previewing: previewing ?? this.previewing,
    run: run ?? this.run,
    error: error == null ? this.error : error(),
  );

  @override
  List<Object?> get props => [
    project,
    app,
    status,
    workflows,
    workflow,
    outline,
    flavors,
    platforms,
    ref,
    refKind,
    bump,
    version,
    inputs,
    invalidInputs,
    releases,
    preview,
    previewing,
    run,
    error,
  ];
}

/// The states of a release that a store has: a patch or a new build can
/// name it.
const _reachedAStore = <ReleaseState>{
  ReleaseState.uploaded,
  ReleaseState.inReview,
  ReleaseState.approved,
  ReleaseState.live,
  ReleaseState.merged,
};

/// [release] as a release input takes it: `x.y.z+build`.
String releaseValue(Release release) => '${release.version}+${release.build}';

List<String> _toggle(List<String> values, String value) =>
    values.contains(value)
    ? [...values.where((item) => item != value)]
    : [...values, value];

/// The Dispatch sheet: picks a workflow and what to run it for, its inputs
/// (the last dispatch's to begin with), previews where each job lands and
/// which gates it hits, and dispatches.
class DispatchBloc extends Bloc<DispatchEvent, DispatchState> {
  new({
    required this._workflows,
    required this._releases,
    required Project project,
  }) : super(
         DispatchState(
           project: project,
           app: project.profile.apps.firstOrNull?.path ?? '.',
           ref: project.defaultBaseBranch,
         ),
       ) {
    on<DispatchStarted>(_onStarted, transformer: droppable());
    on<DispatchWorkflowChanged>(_onWorkflow, transformer: restartable());
    on<DispatchAppChanged>(
      (event, emit) => _changed(
        emit,
        state.copyWith(
          app: event.app,
          flavors: () => null,
          platforms: () => null,
        ),
      ),
    );
    on<DispatchFlavorToggled>(
      (event, emit) => _changed(
        emit,
        state.copyWith(
          flavors: () => _toggle(state.chosenFlavors, event.flavor),
        ),
      ),
    );
    on<DispatchPlatformToggled>(
      (event, emit) => _changed(
        emit,
        state.copyWith(
          platforms: () => _toggle(state.chosenPlatforms, event.platform),
        ),
      ),
    );
    on<DispatchRefChanged>(
      (event, emit) => _changed(emit, state.copyWith(ref: event.ref)),
    );
    on<DispatchRefKindChanged>(
      (event, emit) => emit(state.copyWith(refKind: event.kind)),
    );
    on<DispatchBumpChanged>(
      (event, emit) => _changed(emit, state.copyWith(bump: event.bump)),
    );
    on<DispatchVersionChanged>(
      (event, emit) => _changed(emit, state.copyWith(version: event.version)),
    );
    on<DispatchInputChanged>(
      (event, emit) => _changed(
        emit,
        state.copyWith(
          inputs: {...state.inputs, event.name: event.value},
          invalidInputs: event.valid
              ? ({...state.invalidInputs}..remove(event.name))
              : {...state.invalidInputs, event.name},
        ),
      ),
    );
    on<_DispatchPreviewRequested>(_onPreview, transformer: restartable());
    on<DispatchSubmitted>(_onSubmitted, transformer: droppable());
  }

  final WorkflowsRepository _workflows;
  final ReleasesRepository _releases;

  void _changed(Emitter<DispatchState> emit, DispatchState next) {
    emit(next.copyWith(previewing: true));
    add(const _DispatchPreviewRequested());
  }

  Future<void> _onStarted(
    DispatchStarted event,
    Emitter<DispatchState> emit,
  ) async {
    try {
      final workflows = await _workflows.listWorkflows(state.project.id);
      emit(state.copyWith(workflows: workflows));
      if (workflows.isEmpty) {
        emit(state.copyWith(status: DispatchStatus.ready));
        return;
      }
      add(DispatchWorkflowChanged(workflows.first.id));
    } on Exception catch (error) {
      emit(
        state.copyWith(
          status: DispatchStatus.ready,
          error: () => errorMessage(error),
        ),
      );
    }
  }

  Future<void> _onWorkflow(
    DispatchWorkflowChanged event,
    Emitter<DispatchState> emit,
  ) async {
    emit(state.copyWith(previewing: true, error: () => null));
    try {
      final workflow = await _workflows.getWorkflow(
        state.project.id,
        event.workflowId,
      );
      WorkflowOutline? outline;
      try {
        outline = WorkflowOutline.parse(workflow.yaml);
      } on FormatException {
        outline = const WorkflowOutline();
      }
      final remembered = await _workflows.lastInputs(
        state.project.id,
        workflow.id,
      );
      emit(
        state.copyWith(
          workflow: workflow,
          outline: outline,
          flavors: () => null,
          platforms: () => null,
          inputs: remembered,
          invalidInputs: const {},
          releases: () => null,
        ),
      );
      if (state.releaseInput case final input?) {
        final snapshot =
            (await _releases
                    .watchReleases(projectId: state.project.id)
                    .take(1)
                    .toList())
                .firstOrNull;
        final releases = [
          for (final release in snapshot?.value ?? const <Release>[])
            if (_reachedAStore.contains(release.state)) release,
        ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        emit(
          state.copyWith(
            releases: () => releases,
            inputs: {
              ...state.inputs,
              if (state.inputs[input.name] == null && releases.isNotEmpty)
                input.name: releaseValue(releases.first),
            },
          ),
        );
      }
      add(const _DispatchPreviewRequested());
    } on Exception catch (error) {
      emit(
        state.copyWith(
          status: DispatchStatus.ready,
          previewing: false,
          error: () => errorMessage(error),
        ),
      );
    }
  }

  Future<void> _onPreview(
    _DispatchPreviewRequested event,
    Emitter<DispatchState> emit,
  ) async {
    final workflow = state.workflow;
    if (workflow == null) return;
    try {
      final preview = await _workflows.preview(
        project: state.project,
        workflow: workflow,
        request: state.request,
      );
      emit(
        state.copyWith(
          status: DispatchStatus.ready,
          preview: preview,
          previewing: false,
          error: () => null,
        ),
      );
    } on Exception catch (error) {
      emit(
        state.copyWith(
          status: DispatchStatus.ready,
          previewing: false,
          error: () => errorMessage(error),
        ),
      );
    }
  }

  Future<void> _onSubmitted(
    DispatchSubmitted event,
    Emitter<DispatchState> emit,
  ) async {
    if (!state.canDispatch) return;
    emit(state.copyWith(status: DispatchStatus.submitting, error: () => null));
    try {
      final request = state.request;
      final run = await _workflows.dispatch(
        state.project.id,
        state.workflow!.id,
        request,
      );
      await _workflows.rememberInputs(
        state.project.id,
        state.workflow!.id,
        request.inputs,
      );
      emit(state.copyWith(status: DispatchStatus.dispatched, run: run));
    } on Exception catch (error) {
      emit(
        state.copyWith(
          status: DispatchStatus.ready,
          error: () => errorMessage(error),
        ),
      );
    }
  }
}

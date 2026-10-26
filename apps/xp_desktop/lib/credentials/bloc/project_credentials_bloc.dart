import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_repositories/xp_repositories.dart';

sealed class ProjectCredentialsEvent extends Equatable {
  const new();

  @override
  List<Object?> get props => [];
}

/// Starts following the credentials the flavors of [projectId] use, and the
/// named credentials they may be given.
final class ProjectCredentialsSubscriptionRequested
    extends ProjectCredentialsEvent {
  const new(this.projectId);

  final String projectId;

  @override
  List<Object?> get props => [projectId];
}

/// How to assign a credential: to the flavor [flavor] of the app at [app],
/// or to every flavor of the app with [allFlavors] (those that have their
/// own credential of the kind keep it unless [replace]).
class AssignmentScope extends Equatable {
  const new({
    required this.app,
    required this.flavor,
    this.allFlavors = false,
    this.replace = false,
  });

  final String app;
  final String flavor;
  final bool allFlavors;
  final bool replace;

  @override
  List<Object?> get props => [app, flavor, allFlavors, replace];
}

/// Assigns the named credential [credentialId] for [kind] within [scope].
final class ProjectCredentialAssignRequested extends ProjectCredentialsEvent {
  const new({
    required this.scope,
    required this.kind,
    required this.credentialId,
  });

  final AssignmentScope scope;
  final CredentialKind kind;
  final String credentialId;

  @override
  List<Object?> get props => [scope, kind, credentialId];
}

/// Checks and stores the credential of [request], then assigns it within
/// [scope].
final class ProjectCredentialCreateRequested extends ProjectCredentialsEvent {
  const new({required this.scope, required this.request});

  final AssignmentScope scope;
  final CreateCredentialRequest request;

  @override
  List<Object?> get props => [scope, request];
}

/// The engine creates an Apple Distribution certificate with the App Store
/// Connect key of the flavor [flavor] of the app at [app], and assigns the
/// identity, called [name], to the flavor (ADR 0014).
final class ProjectCertificateCreateRequested extends ProjectCredentialsEvent {
  const new({required this.app, required this.flavor, required this.name});

  final String app;
  final String flavor;
  final String name;

  @override
  List<Object?> get props => [app, flavor, name];
}

/// The flavor [flavor] of the app at [app] stops using its credential of
/// [kind].
final class ProjectCredentialUnassignRequested extends ProjectCredentialsEvent {
  const new({required this.app, required this.flavor, required this.kind});

  final String app;
  final String flavor;
  final CredentialKind kind;

  @override
  List<Object?> get props => [app, flavor, kind];
}

/// An assignment editor opened: forget how the last one went.
final class ProjectCredentialEditorReset extends ProjectCredentialsEvent {
  const new();
}

enum AssignStatus { idle, working, done, failed }

class ProjectCredentialsState extends Equatable {
  const new({
    this.projectId,
    this.loaded = false,
    this.assignments = const [],
    this.named = const [],
    this.assign = AssignStatus.idle,
    this.busy,
    this.kept = const [],
    this.error,
  });

  final String? projectId;

  /// Whether the assignments arrived (from the cache or the engine).
  final bool loaded;

  /// The credential each flavor uses, one per flavor and kind that has one.
  final List<Credential> assignments;

  /// The named credentials of the engine, to choose from.
  final List<NamedCredential> named;

  /// Where the last assignment (or creation and assignment) stands.
  final AssignStatus assign;

  /// The kind being assigned or unassigned.
  final CredentialKind? busy;

  /// The flavors that kept their own credential at the last assignment.
  final List<Credential> kept;

  /// What the engine said when a command failed.
  final String? error;

  /// The credentials the flavor [flavor] of the app at [app] uses.
  List<Credential> of(String app, String flavor) => [
    for (final credential in assignments)
      if (credential.app == app && credential.flavor == flavor) credential,
  ];

  /// The named credentials of [kind].
  List<NamedCredential> choices(CredentialKind kind) => [
    for (final credential in named)
      if (credential.kind == kind) credential,
  ];

  ProjectCredentialsState copyWith({
    bool? loaded,
    List<Credential>? assignments,
    List<NamedCredential>? named,
    AssignStatus? assign,
    CredentialKind? Function()? busy,
    List<Credential>? kept,
    String? Function()? error,
  }) => ProjectCredentialsState(
    projectId: projectId,
    loaded: loaded ?? this.loaded,
    assignments: assignments ?? this.assignments,
    named: named ?? this.named,
    assign: assign ?? this.assign,
    busy: busy == null ? this.busy : busy(),
    kept: kept ?? this.kept,
    error: error == null ? this.error : error(),
  );

  @override
  List<Object?> get props => [
    projectId,
    loaded,
    assignments,
    named,
    assign,
    busy,
    kept,
    error,
  ];
}

/// The credentials of the flavors of one project: which named credential
/// each flavor uses for each kind, with what the checks found, and
/// assigning (to one flavor or every flavor of an app), creating and
/// assigning, creating a distribution certificate, and unassigning.
class ProjectCredentialsBloc
    extends Bloc<ProjectCredentialsEvent, ProjectCredentialsState> {
  new({required this._projects, required this._credentials})
    : super(const ProjectCredentialsState()) {
    on<ProjectCredentialsSubscriptionRequested>(
      _onSubscribe,
      transformer: restartable(),
    );
    on<ProjectCredentialAssignRequested>(
      (event, emit) => _assign(
        emit,
        event.kind,
        () => _assignTo(event.scope, event.kind, event.credentialId),
      ),
      transformer: droppable(),
    );
    on<ProjectCredentialCreateRequested>(
      (event, emit) => _assign(emit, event.request.kind, () async {
        final credential = await _credentials.createCredential(event.request);
        return await _assignTo(event.scope, credential.kind, credential.id);
      }),
      transformer: droppable(),
    );
    on<ProjectCertificateCreateRequested>(
      (event, emit) =>
          _assign(emit, CredentialKind.appleDistribution, () async {
            await _credentials.createDistributionCertificate(
              state.projectId!,
              app: event.app,
              flavor: event.flavor,
              name: event.name,
            );
            return const AssignCredentialResponse(assigned: []);
          }),
      transformer: droppable(),
    );
    on<ProjectCredentialUnassignRequested>(
      _onUnassign,
      transformer: droppable(),
    );
    on<ProjectCredentialEditorReset>(
      (_, emit) => emit(
        state.copyWith(
          assign: AssignStatus.idle,
          kept: const [],
          error: () => null,
        ),
      ),
    );
  }

  final ProjectsRepository _projects;
  final CredentialsRepository _credentials;

  Future<void> _onSubscribe(
    ProjectCredentialsSubscriptionRequested event,
    Emitter<ProjectCredentialsState> emit,
  ) async {
    emit(ProjectCredentialsState(projectId: event.projectId));
    final assignments = emit.forEach<Snapshot<List<Credential>>>(
      _projects.watchCredentials(event.projectId),
      onData: (snapshot) =>
          state.copyWith(loaded: true, assignments: snapshot.value),
      onError: (error, _) =>
          state.copyWith(loaded: true, error: () => errorMessage(error)),
    );
    final named = emit.forEach<Snapshot<List<NamedCredential>>>(
      _credentials.watchCredentials(),
      onData: (snapshot) => state.copyWith(named: snapshot.value),
      onError: (error, _) => state.copyWith(error: () => errorMessage(error)),
    );
    await Future.wait([assignments, named]);
  }

  Future<AssignCredentialResponse> _assignTo(
    AssignmentScope scope,
    CredentialKind kind,
    String credentialId,
  ) => _projects.assignCredential(
    state.projectId!,
    app: scope.app,
    flavor: scope.flavor,
    kind: kind,
    credentialId: credentialId,
    allFlavors: scope.allFlavors,
    replace: scope.allFlavors && scope.replace,
  );

  Future<void> _assign(
    Emitter<ProjectCredentialsState> emit,
    CredentialKind kind,
    Future<AssignCredentialResponse> Function() assign,
  ) async {
    if (state.projectId == null) return;
    emit(
      state.copyWith(
        assign: AssignStatus.working,
        busy: () => kind,
        kept: const [],
        error: () => null,
      ),
    );
    try {
      final response = await assign();
      emit(
        state.copyWith(
          assign: AssignStatus.done,
          busy: () => null,
          kept: response.kept,
        ),
      );
    } on Exception catch (error) {
      emit(
        state.copyWith(
          assign: AssignStatus.failed,
          busy: () => null,
          error: () => errorMessage(error),
        ),
      );
    }
  }

  Future<void> _onUnassign(
    ProjectCredentialUnassignRequested event,
    Emitter<ProjectCredentialsState> emit,
  ) async {
    final projectId = state.projectId;
    if (projectId == null) return;
    emit(state.copyWith(busy: () => event.kind, error: () => null));
    try {
      await _projects.unassignCredential(
        projectId,
        app: event.app,
        flavor: event.flavor,
        kind: event.kind,
      );
      emit(state.copyWith(busy: () => null));
    } on Exception catch (error) {
      emit(state.copyWith(busy: () => null, error: () => errorMessage(error)));
    }
  }
}

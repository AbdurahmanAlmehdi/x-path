import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/project_overview/bloc/project_overview_bloc.dart'
    show inFlightStates;
import 'package:xp_repositories/xp_repositories.dart';

sealed class ReleaseBoardEvent extends Equatable {
  const new();

  @override
  List<Object?> get props => [];
}

/// Starts following the releases of [projectId], showing [releaseId] if
/// given, else the one in flight.
final class ReleaseBoardSubscriptionRequested extends ReleaseBoardEvent {
  const new(this.projectId, {this.releaseId});

  final String projectId;
  final String? releaseId;

  @override
  List<Object?> get props => [projectId, releaseId];
}

/// Shows [releaseId].
final class ReleaseBoardReleaseSelected extends ReleaseBoardEvent {
  const new(this.releaseId);

  final String releaseId;

  @override
  List<Object?> get props => [releaseId];
}

/// Asks the stores about the shown release now.
final class ReleaseBoardRefreshRequested extends ReleaseBoardEvent {
  const new();
}

/// Says by hand that [store] is in [state] ("Mark approved", "Mark live").
final class ReleaseBoardStoreMarked extends ReleaseBoardEvent {
  const new(this.store, this.state);

  final ReleaseStore store;
  final StoreState state;

  @override
  List<Object?> get props => [store, state];
}

/// Asks to merge the release pull request.
final class ReleaseBoardMergeRequested extends ReleaseBoardEvent {
  const new();
}

/// Builds the rejected version again with a new build number.
final class ReleaseBoardNewBuildRequested extends ReleaseBoardEvent {
  const new();
}

final class _ReleaseBoardNotesRequested extends ReleaseBoardEvent {
  const new(this.releaseId);

  final String releaseId;
}

/// What the board is sending to the engine.
enum ReleaseCommand { none, refreshing, marking, merging, building }

class ReleaseBoardState extends Equatable {
  const new({
    this.loaded = false,
    this.releases = const [],
    this.cached = false,
    this.selectedId,
    this.approvals = const [],
    this.credentials = const [],
    this.notes,
    this.notesError,
    this.command = ReleaseCommand.none,
    this.error,
    this.builtRun,
  });

  /// Whether the releases arrived (from the cache or the engine).
  final bool loaded;

  /// The releases of the project, newest first.
  final List<Release> releases;

  /// Whether [releases] came from the offline cache.
  final bool cached;

  /// The release picked, if any.
  final String? selectedId;

  /// The approvals of the project, for the timeline.
  final List<Approval> approvals;

  /// The credentials of the project: a store without its API credential is
  /// marked by hand (D-14, D-15).
  final List<Credential> credentials;

  /// The notes of the shown release.
  final ReleaseNotes? notes;

  /// Why the notes could not be read.
  final String? notesError;

  final ReleaseCommand command;

  /// What the engine said when the last command failed.
  final String? error;

  /// The run a "New build, same version" started.
  final Run? builtRun;

  /// The release shown: the one picked, else the newest in flight, else the
  /// newest.
  Release? get release {
    for (final release in releases) {
      if (release.id == selectedId) return release;
    }
    for (final release in releases) {
      if (inFlightStates.contains(release.state)) return release;
    }
    return releases.firstOrNull;
  }

  /// Whether the engine reads [store] for [release] through its API: the
  /// flavor has an App Store Connect key or a Play service account. Without
  /// one the owner marks the store by hand.
  bool readsStore(Release release, ReleaseStore store) {
    final kind = switch (store) {
      ReleaseStore.apple => CredentialKind.ascKey,
      ReleaseStore.play => CredentialKind.playSa,
    };
    return credentials.any(
      (credential) =>
          credential.kind == kind &&
          credential.app == release.app &&
          credential.flavor == release.flavor,
    );
  }

  ReleaseBoardState copyWith({
    bool? loaded,
    List<Release>? releases,
    bool? cached,
    String? Function()? selectedId,
    List<Approval>? approvals,
    List<Credential>? credentials,
    ReleaseNotes? Function()? notes,
    String? Function()? notesError,
    ReleaseCommand? command,
    String? Function()? error,
    Run? Function()? builtRun,
  }) => ReleaseBoardState(
    loaded: loaded ?? this.loaded,
    releases: releases ?? this.releases,
    cached: cached ?? this.cached,
    selectedId: selectedId == null ? this.selectedId : selectedId(),
    approvals: approvals ?? this.approvals,
    credentials: credentials ?? this.credentials,
    notes: notes == null ? this.notes : notes(),
    notesError: notesError == null ? this.notesError : notesError(),
    command: command ?? this.command,
    error: error == null ? this.error : error(),
    builtRun: builtRun == null ? this.builtRun : builtRun(),
  );

  @override
  List<Object?> get props => [
    loaded,
    releases,
    cached,
    selectedId,
    approvals,
    credentials,
    notes,
    notesError,
    command,
    error,
    builtRun,
  ];
}

/// The releases of a project (concept 3A): the release shown with its store
/// lanes, timeline and notes; refresh, the manual store buttons, "New build,
/// same version" and Merge.
class ReleaseBoardBloc extends Bloc<ReleaseBoardEvent, ReleaseBoardState> {
  new({
    required this._releases,
    required this._approvals,
    required this._projects,
  }) : super(const ReleaseBoardState()) {
    on<ReleaseBoardSubscriptionRequested>(
      _onSubscribe,
      transformer: restartable(),
    );
    on<ReleaseBoardReleaseSelected>(
      (event, emit) =>
          _show(emit, state.copyWith(selectedId: () => event.releaseId)),
    );
    on<_ReleaseBoardNotesRequested>(_onNotes, transformer: restartable());
    on<ReleaseBoardRefreshRequested>(_onRefresh, transformer: droppable());
    on<ReleaseBoardStoreMarked>(_onMark, transformer: droppable());
    on<ReleaseBoardMergeRequested>(_onMerge, transformer: droppable());
    on<ReleaseBoardNewBuildRequested>(_onNewBuild, transformer: droppable());
  }

  final ReleasesRepository _releases;
  final ApprovalsRepository _approvals;
  final ProjectsRepository _projects;

  /// The release and commit the notes were read for.
  (String, String)? _notesOf;

  /// Emits [next], and reads the notes of its release when that release or
  /// its commit changed. A release without a commit has no notes yet.
  void _show(Emitter<ReleaseBoardState> emit, ReleaseBoardState next) {
    final release = next.release;
    final sha = release?.headSha;
    final key = release == null || sha == null ? null : (release.id, sha);
    if (key == _notesOf) {
      emit(next);
      return;
    }
    _notesOf = key;
    emit(next.copyWith(notes: () => null, notesError: () => null));
    if (key != null) add(_ReleaseBoardNotesRequested(key.$1));
  }

  Future<void> _onSubscribe(
    ReleaseBoardSubscriptionRequested event,
    Emitter<ReleaseBoardState> emit,
  ) async {
    // Read again (Retry): what failed before no longer stands.
    emit(state.copyWith(selectedId: () => event.releaseId, error: () => null));
    final releases = emit.forEach<Snapshot<List<Release>>>(
      _releases.watchReleases(projectId: event.projectId),
      onData: (snapshot) {
        _show(
          emit,
          state.copyWith(
            loaded: true,
            releases: snapshot.value,
            cached: snapshot.cached,
          ),
        );
        return state;
      },
      onError: (error, _) =>
          state.copyWith(loaded: true, error: () => errorMessage(error)),
    );
    final approvals = emit.forEach<Snapshot<List<Approval>>>(
      _approvals.watchApprovals(projectId: event.projectId),
      onData: (snapshot) => state.copyWith(approvals: snapshot.value),
      onError: (_, _) => state,
    );
    final credentials = emit.forEach<Snapshot<List<Credential>>>(
      _projects.watchCredentials(event.projectId),
      onData: (snapshot) => state.copyWith(credentials: snapshot.value),
      onError: (_, _) => state,
    );
    await Future.wait([releases, approvals, credentials]);
  }

  Future<void> _onNotes(
    _ReleaseBoardNotesRequested event,
    Emitter<ReleaseBoardState> emit,
  ) async {
    try {
      final notes = await _releases.notes(event.releaseId);
      if (state.release?.id == event.releaseId) {
        emit(state.copyWith(notes: () => notes, notesError: () => null));
      }
    } on Exception catch (error) {
      if (state.release?.id == event.releaseId) {
        emit(state.copyWith(notesError: () => errorMessage(error)));
      }
    }
  }

  /// Sends [command] for the shown release; the release events bring the
  /// result to the list.
  Future<void> _command(
    Emitter<ReleaseBoardState> emit,
    ReleaseCommand command,
    Future<Object?> Function(Release release) send, {
    Run? Function(Object? result)? builtRun,
  }) async {
    final release = state.release;
    if (release == null) return;
    emit(state.copyWith(command: command, error: () => null));
    try {
      final result = await send(release);
      emit(
        state.copyWith(
          command: ReleaseCommand.none,
          builtRun: builtRun == null ? null : () => builtRun(result),
        ),
      );
    } on Exception catch (error) {
      emit(
        state.copyWith(
          command: ReleaseCommand.none,
          error: () => errorMessage(error),
        ),
      );
    }
  }

  Future<void> _onRefresh(
    ReleaseBoardRefreshRequested event,
    Emitter<ReleaseBoardState> emit,
  ) => _command(
    emit,
    ReleaseCommand.refreshing,
    (release) => _releases.refresh(release.id),
  );

  Future<void> _onMark(
    ReleaseBoardStoreMarked event,
    Emitter<ReleaseBoardState> emit,
  ) => _command(
    emit,
    ReleaseCommand.marking,
    (release) => _releases.setStoreStatus(release.id, event.store, event.state),
  );

  Future<void> _onMerge(
    ReleaseBoardMergeRequested event,
    Emitter<ReleaseBoardState> emit,
  ) => _command(
    emit,
    ReleaseCommand.merging,
    (release) => _releases.merge(release.id),
  );

  Future<void> _onNewBuild(
    ReleaseBoardNewBuildRequested event,
    Emitter<ReleaseBoardState> emit,
  ) => _command(
    emit,
    ReleaseCommand.building,
    (release) => _releases.startBuild(release.id),
    builtRun: (result) => result! as Run,
  );
}

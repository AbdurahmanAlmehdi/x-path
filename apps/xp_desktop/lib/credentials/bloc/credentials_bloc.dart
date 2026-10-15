import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_repositories/xp_repositories.dart';

sealed class CredentialsEvent extends Equatable {
  const new();
}

/// Starts following the credentials of [projectId].
final class CredentialsSubscriptionRequested extends CredentialsEvent {
  const new(this.projectId);

  final String projectId;

  @override
  List<Object?> get props => [projectId];
}

/// Checks and saves [request].
final class CredentialSaveRequested extends CredentialsEvent {
  const new(this.request);

  final SaveCredentialRequest request;

  @override
  List<Object?> get props => [request];
}

/// The form opened or closed: forget the last save.
final class CredentialFormReset extends CredentialsEvent {
  const new();

  @override
  List<Object?> get props => [];
}

/// Checks [credentialId] again now.
final class CredentialVerifyRequested extends CredentialsEvent {
  const new(this.credentialId);

  final String credentialId;

  @override
  List<Object?> get props => [credentialId];
}

/// Deletes [credentialId].
final class CredentialDeleteRequested extends CredentialsEvent {
  const new(this.credentialId);

  final String credentialId;

  @override
  List<Object?> get props => [credentialId];
}

enum CredentialSaveStatus { idle, saving, saved, failed }

class CredentialsState extends Equatable {
  const new({
    this.projectId,
    this.loaded = false,
    this.credentials = const [],
    this.cached = false,
    this.save = CredentialSaveStatus.idle,
    this.saveError,
    this.busy,
    this.error,
  });

  final String? projectId;
  final bool loaded;
  final List<Credential> credentials;

  /// Whether [credentials] came from the offline cache.
  final bool cached;

  /// Where the form's save stands.
  final CredentialSaveStatus save;

  /// Why the engine refused to save (nothing was stored).
  final String? saveError;

  /// The credential being checked or deleted.
  final String? busy;

  /// What the engine said when a check or a delete failed.
  final String? error;

  CredentialsState copyWith({
    CredentialSaveStatus? save,
    String? saveError,
    String? busy,
    String? error,
  }) => CredentialsState(
    projectId: projectId,
    loaded: loaded,
    credentials: credentials,
    cached: cached,
    save: save ?? this.save,
    saveError: saveError,
    busy: busy,
    error: error,
  );

  @override
  List<Object?> get props => [
    projectId,
    loaded,
    credentials,
    cached,
    save,
    saveError,
    busy,
    error,
  ];
}

/// The credentials editor of one project: the list with each check's
/// result, adding or replacing one (the engine checks it first and stores
/// nothing it refuses), checking again and deleting.
class CredentialsBloc extends Bloc<CredentialsEvent, CredentialsState> {
  new({required this._projects}) : super(const CredentialsState()) {
    on<CredentialsSubscriptionRequested>(
      _onSubscribe,
      transformer: restartable(),
    );
    on<CredentialSaveRequested>(_onSave, transformer: droppable());
    on<CredentialFormReset>(
      (_, emit) => emit(state.copyWith(save: CredentialSaveStatus.idle)),
    );
    on<CredentialVerifyRequested>(_onVerify, transformer: droppable());
    on<CredentialDeleteRequested>(_onDelete, transformer: droppable());
  }

  final ProjectsRepository _projects;

  Future<void> _onSubscribe(
    CredentialsSubscriptionRequested event,
    Emitter<CredentialsState> emit,
  ) async {
    emit(CredentialsState(projectId: event.projectId));
    await emit.forEach<Snapshot<List<Credential>>>(
      _projects.watchCredentials(event.projectId),
      onData: (snapshot) => CredentialsState(
        projectId: event.projectId,
        loaded: true,
        credentials: snapshot.value,
        cached: snapshot.cached,
        save: state.save,
        busy: state.busy,
      ),
      onError: (error, _) => state.copyWith(error: errorMessage(error)),
    );
  }

  Future<void> _onSave(
    CredentialSaveRequested event,
    Emitter<CredentialsState> emit,
  ) async {
    final projectId = state.projectId;
    if (projectId == null) return;
    emit(state.copyWith(save: CredentialSaveStatus.saving));
    try {
      await _projects.saveCredential(projectId, event.request);
      emit(state.copyWith(save: CredentialSaveStatus.saved));
    } on Exception catch (error) {
      emit(
        state.copyWith(
          save: CredentialSaveStatus.failed,
          saveError: errorMessage(error),
        ),
      );
    }
  }

  Future<void> _onVerify(
    CredentialVerifyRequested event,
    Emitter<CredentialsState> emit,
  ) => _command(
    event.credentialId,
    emit,
    () => _projects.verifyCredential(state.projectId!, event.credentialId),
  );

  Future<void> _onDelete(
    CredentialDeleteRequested event,
    Emitter<CredentialsState> emit,
  ) => _command(
    event.credentialId,
    emit,
    () => _projects.deleteCredential(state.projectId!, event.credentialId),
  );

  Future<void> _command(
    String credentialId,
    Emitter<CredentialsState> emit,
    Future<void> Function() run,
  ) async {
    if (state.projectId == null) return;
    emit(state.copyWith(busy: credentialId));
    try {
      await run();
      emit(state.copyWith());
    } on Exception catch (error) {
      emit(state.copyWith(error: errorMessage(error)));
    }
  }
}

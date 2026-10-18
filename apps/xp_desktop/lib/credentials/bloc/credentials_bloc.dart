import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_repositories/xp_repositories.dart';

sealed class CredentialsEvent extends Equatable {
  const new();

  @override
  List<Object?> get props => [];
}

/// Starts following the named credentials of the engine.
final class CredentialsSubscriptionRequested extends CredentialsEvent {
  const new();
}

/// Checks and stores the new credential of [request].
final class CredentialCreateRequested extends CredentialsEvent {
  const new(this.request);

  final CreateCredentialRequest request;

  @override
  List<Object?> get props => [request];
}

/// Checks the secret of [request] and gives it to [credentialId].
final class CredentialReplaceRequested extends CredentialsEvent {
  const new(this.credentialId, this.request);

  final String credentialId;
  final ReplaceCredentialRequest request;

  @override
  List<Object?> get props => [credentialId, request];
}

/// The form opened or closed: forget the last save.
final class CredentialFormReset extends CredentialsEvent {
  const new();
}

/// Gives [credentialId] the name [name].
final class CredentialRenameRequested extends CredentialsEvent {
  const new(this.credentialId, this.name);

  final String credentialId;
  final String name;

  @override
  List<Object?> get props => [credentialId, name];
}

/// Checks [credentialId], and where it is used, again now.
final class CredentialVerifyRequested extends CredentialsEvent {
  const new(this.credentialId);

  final String credentialId;

  @override
  List<Object?> get props => [credentialId];
}

/// Deletes [credentialId]; with [force], unassigns it from the flavors that
/// use it first.
final class CredentialDeleteRequested extends CredentialsEvent {
  const new(this.credentialId, {this.force = false});

  final String credentialId;
  final bool force;

  @override
  List<Object?> get props => [credentialId, force];
}

enum CredentialSaveStatus { idle, saving, saved, failed }

/// A credential the engine did not delete because flavors use it.
class CredentialConflict extends Equatable {
  const new(this.credentialId, this.usedBy);

  final String credentialId;

  /// The flavors that use it.
  final List<CredentialUsage> usedBy;

  @override
  List<Object?> get props => [credentialId, usedBy];
}

class CredentialsState extends Equatable {
  const new({
    this.loaded = false,
    this.credentials = const [],
    this.cached = false,
    this.save = CredentialSaveStatus.idle,
    this.saveError,
    this.busy,
    this.error,
    this.inUse,
  });

  final bool loaded;

  /// The named credentials, by name.
  final List<NamedCredential> credentials;

  /// Whether [credentials] came from the offline cache.
  final bool cached;

  /// Where the form's save stands.
  final CredentialSaveStatus save;

  /// Why the engine refused to save (nothing was stored).
  final String? saveError;

  /// The credential being renamed, checked or deleted.
  final String? busy;

  /// What the engine said when a command failed.
  final String? error;

  /// The credential the engine did not delete because flavors use it.
  final CredentialConflict? inUse;

  CredentialsState copyWith({
    CredentialSaveStatus? save,
    String? saveError,
    String? busy,
    String? error,
    CredentialConflict? inUse,
  }) => CredentialsState(
    loaded: loaded,
    credentials: credentials,
    cached: cached,
    save: save ?? this.save,
    saveError: saveError,
    busy: busy,
    error: error,
    inUse: inUse,
  );

  @override
  List<Object?> get props => [
    loaded,
    credentials,
    cached,
    save,
    saveError,
    busy,
    error,
    inUse,
  ];
}

/// The named credentials of the engine: the list with each check's result
/// and the flavors that use each; adding one or replacing its secret (the
/// engine checks it first and stores nothing it refuses), renaming,
/// checking again and deleting.
class CredentialsBloc extends Bloc<CredentialsEvent, CredentialsState> {
  new({required this._credentials}) : super(const CredentialsState()) {
    on<CredentialsSubscriptionRequested>(
      _onSubscribe,
      transformer: restartable(),
    );
    on<CredentialCreateRequested>(
      (event, emit) =>
          _save(emit, () => _credentials.createCredential(event.request)),
      transformer: droppable(),
    );
    on<CredentialReplaceRequested>(
      (event, emit) => _save(
        emit,
        () => _credentials.replaceSecret(event.credentialId, event.request),
      ),
      transformer: droppable(),
    );
    on<CredentialFormReset>(
      (_, emit) => emit(state.copyWith(save: CredentialSaveStatus.idle)),
    );
    on<CredentialRenameRequested>(
      (event, emit) => _command(
        event.credentialId,
        emit,
        () => _credentials.renameCredential(event.credentialId, event.name),
      ),
      transformer: droppable(),
    );
    on<CredentialVerifyRequested>(
      (event, emit) => _command(
        event.credentialId,
        emit,
        () => _credentials.verifyCredential(event.credentialId),
      ),
      transformer: droppable(),
    );
    on<CredentialDeleteRequested>(
      (event, emit) => _command(
        event.credentialId,
        emit,
        () => _credentials.deleteCredential(
          event.credentialId,
          force: event.force,
        ),
      ),
      transformer: droppable(),
    );
  }

  final CredentialsRepository _credentials;

  Future<void> _onSubscribe(
    CredentialsSubscriptionRequested event,
    Emitter<CredentialsState> emit,
  ) => emit.forEach<Snapshot<List<NamedCredential>>>(
    _credentials.watchCredentials(),
    onData: (snapshot) => CredentialsState(
      loaded: true,
      credentials: snapshot.value,
      cached: snapshot.cached,
      save: state.save,
      saveError: state.saveError,
      busy: state.busy,
      inUse: state.inUse,
    ),
    onError: (error, _) => state.copyWith(error: errorMessage(error)),
  );

  Future<void> _save(
    Emitter<CredentialsState> emit,
    Future<void> Function() save,
  ) async {
    emit(state.copyWith(save: CredentialSaveStatus.saving));
    try {
      await save();
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

  Future<void> _command(
    String credentialId,
    Emitter<CredentialsState> emit,
    Future<void> Function() run,
  ) async {
    emit(state.copyWith(busy: credentialId));
    try {
      await run();
      emit(state.copyWith());
    } on CredentialInUse catch (error) {
      emit(
        state.copyWith(inUse: CredentialConflict(credentialId, error.usedBy)),
      );
    } on Exception catch (error) {
      emit(state.copyWith(error: errorMessage(error)));
    }
  }
}

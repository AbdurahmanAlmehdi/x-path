import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_repositories/xp_repositories.dart';

sealed class StorageEvent extends Equatable {
  const new();

  @override
  List<Object?> get props => [];
}

/// Reads what the engine keeps, now and again whenever it is asked.
final class StorageSubscriptionRequested extends StorageEvent {
  const new();
}

/// Frees what retention gives back in [categories] ("free up space").
final class StorageFreeRequested extends StorageEvent {
  const new(this.categories);

  final List<StorageCategory> categories;

  @override
  List<Object?> get props => [categories];
}

/// Replaces the retention settings.
final class StorageRetentionChanged extends StorageEvent {
  const new(this.settings);

  final RetentionSettings settings;

  @override
  List<Object?> get props => [settings];
}

/// What the storage view is sending to the engine.
enum StorageCommand { none, freeing, saving }

class StorageState extends Equatable {
  const new({
    this.loaded = false,
    this.report,
    this.cached = false,
    this.command = StorageCommand.none,
    this.freed,
    this.error,
  });

  /// Whether the report arrived (from the cache or the engine).
  final bool loaded;

  /// What the engine keeps and what housekeeping would give back.
  final StorageReport? report;

  /// Whether [report] came from the offline cache.
  final bool cached;

  final StorageCommand command;

  /// What the last "free up space" gave back.
  final FreeSpaceResult? freed;

  /// What the engine said when the report could not be read or a command
  /// failed.
  final String? error;

  StorageState copyWith({
    bool? loaded,
    StorageReport? report,
    bool? cached,
    StorageCommand? command,
    FreeSpaceResult? Function()? freed,
    String? Function()? error,
  }) => StorageState(
    loaded: loaded ?? this.loaded,
    report: report ?? this.report,
    cached: cached ?? this.cached,
    command: command ?? this.command,
    freed: freed == null ? this.freed : freed(),
    error: error == null ? this.error : error(),
  );

  @override
  List<Object?> get props => [loaded, report, cached, command, freed, error];
}

/// What the engine keeps on its disk (D-22, D-24): the storage view and the
/// "free-able" size in the sidebar. No event says it changed, so it is read
/// again after each command.
class StorageBloc extends Bloc<StorageEvent, StorageState> {
  new({required this._storage}) : super(const StorageState()) {
    on<StorageSubscriptionRequested>((event, emit) {
      // Read again (Retry): what failed before no longer stands.
      if (state.error != null) emit(state.copyWith(error: () => null));
      return emit.forEach<Snapshot<StorageReport>>(
        _storage.watchStorage(),
        onData: (snapshot) => state.copyWith(
          loaded: true,
          report: snapshot.value,
          cached: snapshot.cached,
        ),
        onError: (error, _) =>
            state.copyWith(loaded: true, error: () => errorMessage(error)),
      );
    }, transformer: restartable());
    on<StorageFreeRequested>(_onFree, transformer: droppable());
    on<StorageRetentionChanged>(_onRetention, transformer: droppable());
  }

  final StorageRepository _storage;

  Future<void> _onFree(
    StorageFreeRequested event,
    Emitter<StorageState> emit,
  ) => _command(emit, StorageCommand.freeing, () async {
    final result = await _storage.freeSpace(event.categories);
    emit(state.copyWith(freed: () => result));
  });

  Future<void> _onRetention(
    StorageRetentionChanged event,
    Emitter<StorageState> emit,
  ) => _command(
    emit,
    StorageCommand.saving,
    () => _storage.setRetention(event.settings),
  );

  Future<void> _command(
    Emitter<StorageState> emit,
    StorageCommand command,
    Future<void> Function() send,
  ) async {
    emit(
      state.copyWith(command: command, freed: () => null, error: () => null),
    );
    try {
      await send();
      emit(state.copyWith(command: StorageCommand.none));
      add(const StorageSubscriptionRequested());
    } on Exception catch (error) {
      emit(
        state.copyWith(
          command: StorageCommand.none,
          error: () => errorMessage(error),
        ),
      );
    }
  }
}

import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:xp_repositories/xp_repositories.dart';

sealed class AddEngineEvent extends Equatable {
  const new();
}

/// Checks the engine at [url] with [token] and saves it as [name].
final class AddEngineSubmitted extends AddEngineEvent {
  const new({required this.name, required this.url, required this.token});

  final String name;
  final String url;
  final String token;

  @override
  List<Object?> get props => [name, url, token];
}

enum AddEngineStatus { idle, checking, added, failed }

class AddEngineState extends Equatable {
  const new({this.status = AddEngineStatus.idle, this.failure, this.engine});

  final AddEngineStatus status;

  /// Why the engine was not added.
  final EngineCheckFailure? failure;

  /// The engine that was added.
  final EngineProfile? engine;

  @override
  List<Object?> get props => [status, failure, engine];
}

/// Adds a remote engine by URL and token, after the same checks as
/// `xp connect`.
class AddEngineBloc extends Bloc<AddEngineEvent, AddEngineState> {
  new({required this._engines}) : super(const AddEngineState()) {
    on<AddEngineSubmitted>(_onSubmitted, transformer: droppable());
  }

  final EnginesRepository _engines;

  Future<void> _onSubmitted(
    AddEngineSubmitted event,
    Emitter<AddEngineState> emit,
  ) async {
    emit(const AddEngineState(status: AddEngineStatus.checking));
    try {
      final engine = await _engines.addRemote(
        name: event.name,
        url: event.url,
        token: event.token.trim(),
      );
      emit(AddEngineState(status: AddEngineStatus.added, engine: engine));
    } on EngineCheckException catch (error) {
      emit(
        AddEngineState(status: AddEngineStatus.failed, failure: error.failure),
      );
    }
  }
}

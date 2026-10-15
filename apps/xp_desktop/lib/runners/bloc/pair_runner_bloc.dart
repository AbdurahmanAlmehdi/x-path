import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_repositories/xp_repositories.dart';

sealed class PairRunnerEvent extends Equatable {
  const new();

  @override
  List<Object?> get props => [];
}

/// Makes a pairing token for a runner called [name].
final class PairingTokenRequested extends PairRunnerEvent {
  const new(this.name);

  final String name;

  @override
  List<Object?> get props => [name];
}

enum PairRunnerStatus { idle, creating, created, failed }

class PairRunnerState extends Equatable {
  const new({this.status = PairRunnerStatus.idle, this.token, this.error});

  final PairRunnerStatus status;

  /// The pairing token: shown once, never kept by the app.
  final PairingToken? token;

  /// Why the engine refused (a name in use, a token that may not pair).
  final String? error;

  @override
  List<Object?> get props => [status, token, error];
}

/// The pairing sheet: one single-use pairing token (D-08) for a runner name.
class PairRunnerBloc extends Bloc<PairRunnerEvent, PairRunnerState> {
  new({required this._runners}) : super(const PairRunnerState()) {
    on<PairingTokenRequested>(_onRequested, transformer: droppable());
  }

  final RunnersRepository _runners;

  Future<void> _onRequested(
    PairingTokenRequested event,
    Emitter<PairRunnerState> emit,
  ) async {
    emit(const PairRunnerState(status: PairRunnerStatus.creating));
    try {
      final token = await _runners.createPairingToken(event.name.trim());
      emit(PairRunnerState(status: PairRunnerStatus.created, token: token));
    } on Exception catch (error) {
      emit(
        PairRunnerState(
          status: PairRunnerStatus.failed,
          error: errorMessage(error),
        ),
      );
    }
  }
}

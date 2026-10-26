import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_repositories/xp_repositories.dart';

sealed class CliTokenEvent extends Equatable {
  const new();

  @override
  List<Object?> get props => [];
}

/// Makes a token called [name] for `xp` or `xp mcp` ([kind]).
final class CliTokenRequested extends CliTokenEvent {
  const new({required this.name, required this.kind});

  final String name;
  final DeviceTokenKind kind;

  @override
  List<Object?> get props => [name, kind];
}

/// Forgets the token shown: its secret is never shown again.
final class CliTokenDismissed extends CliTokenEvent {
  const new();
}

class CliTokenState extends Equatable {
  const new({this.creating, this.created, this.error});

  /// The kind of token being made, if one is.
  final DeviceTokenKind? creating;

  /// The token made last, with its secret, until it is dismissed.
  final CreatedToken? created;

  /// What the engine said when it could not make one.
  final String? error;

  @override
  List<Object?> get props => [creating, created, error];
}

/// Settings ▸ CLI and agents (U5b): makes a token for `xp` or an agent, so
/// connecting either needs no access to the `xpd` binary.
class CliTokenBloc extends Bloc<CliTokenEvent, CliTokenState> {
  new({required this._settings}) : super(const CliTokenState()) {
    on<CliTokenRequested>(_onRequested, transformer: droppable());
    on<CliTokenDismissed>((_, emit) => emit(const CliTokenState()));
  }

  final SettingsRepository _settings;

  Future<void> _onRequested(
    CliTokenRequested event,
    Emitter<CliTokenState> emit,
  ) async {
    emit(CliTokenState(creating: event.kind));
    try {
      final created = await _settings.createToken(
        name: event.name,
        kind: event.kind,
      );
      emit(CliTokenState(created: created));
    } on Exception catch (error) {
      emit(CliTokenState(error: errorMessage(error)));
    }
  }
}

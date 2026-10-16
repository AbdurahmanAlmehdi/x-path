import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:xp_macos_services/xp_macos_services.dart';

sealed class CommandLineToolEvent extends Equatable {
  const new();

  @override
  List<Object?> get props => [];
}

/// Reads where `xp` stands.
final class CommandLineToolRequested extends CommandLineToolEvent {
  const new();
}

/// Links the bundled `xp` into the `PATH`, replacing a link into another
/// copy of XPath.
final class CommandLineToolLinkRequested extends CommandLineToolEvent {
  const new();
}

class CommandLineToolState extends Equatable {
  const new({this.link, this.linking = false});

  /// Where `xp` stands, once read.
  final CliLink? link;

  /// Whether the link is being made.
  final bool linking;

  @override
  List<Object?> get props => [link, linking];
}

/// The "Command line tool" of the settings: where `xp` is linked, and
/// "Link xp" when it is not, or when it points into another copy of XPath.
/// It goes through the same [CliLinker] as onboarding.
class CommandLineToolBloc
    extends Bloc<CommandLineToolEvent, CommandLineToolState> {
  new({required this._linker}) : super(const CommandLineToolState()) {
    on<CommandLineToolRequested>(
      (event, emit) async =>
          emit(CommandLineToolState(link: await _linker.status())),
      transformer: restartable(),
    );
    on<CommandLineToolLinkRequested>(_onLink, transformer: droppable());
  }

  final CliLinker _linker;

  Future<void> _onLink(
    CommandLineToolLinkRequested event,
    Emitter<CommandLineToolState> emit,
  ) async {
    emit(CommandLineToolState(link: state.link, linking: true));
    emit(CommandLineToolState(link: await _linker.link()));
  }
}

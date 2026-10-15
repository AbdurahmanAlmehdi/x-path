import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:xp_macos_services/xp_macos_services.dart';
import 'package:xp_repositories/xp_repositories.dart';

sealed class RemoveXPathEvent extends Equatable {
  const new();

  @override
  List<Object?> get props => [];
}

/// The owner confirmed "Remove XPath", with the options of the sheet.
final class RemoveXPathConfirmed extends RemoveXPathEvent {
  const new({required this.deleteData, required this.deleteKeychain});

  /// "Also delete engine data".
  final bool deleteData;

  /// "Also delete Keychain items".
  final bool deleteKeychain;

  @override
  List<Object?> get props => [deleteData, deleteKeychain];
}

/// Moves `XPath.app` to the Trash, then quits.
final class RemoveXPathTrashRequested extends RemoveXPathEvent {
  const new();
}

/// Quits without the Trash (the owner drags the app there).
final class RemoveXPathQuitRequested extends RemoveXPathEvent {
  const new();
}

/// What removing XPath does, in order.
enum RemovalStep {
  /// Revoke every runner of the engine on this Mac, while it still runs.
  runners,

  /// Unregister the engine's login item; launchd stops it.
  engine,

  /// Remove the `xp` link, if it points into this app.
  cli,

  /// Delete the engine's data folder and the app's engine list and cache.
  data,

  /// Delete the Keychain items of the engine and the app.
  keychain,
}

enum RemovalStepState { pending, working, done, skipped, failed }

/// Where one [step] stands.
class RemovalStepResult extends Equatable {
  const new(this.step, this.state, {this.detail, this.count});

  final RemovalStep step;
  final RemovalStepState state;

  /// What macOS or the engine said when the step failed.
  final String? detail;

  /// How many runners were revoked, or Keychain items deleted.
  final int? count;

  @override
  List<Object?> get props => [step, state, detail, count];
}

/// Where removing XPath stands.
enum RemovalPhase {
  /// The sheet asks.
  idle,

  /// The steps run.
  removing,

  /// The steps ran; the app is still in place.
  removed,

  /// Moving the app to the Trash, then quitting.
  leaving,

  /// The app could not move itself to the Trash.
  trashFailed,
}

class RemoveXPathState extends Equatable {
  const new({this.phase = RemovalPhase.idle, this.steps = const []});

  final RemovalPhase phase;

  /// The steps chosen, in order.
  final List<RemovalStepResult> steps;

  RemoveXPathState withStep(RemovalStepResult result) => RemoveXPathState(
    phase: phase,
    steps: [
      for (final step in steps)
        if (step.step == result.step) result else step,
    ],
  );

  @override
  List<Object?> get props => [phase, steps];
}

/// "Remove XPath": revokes the runner tokens while the engine still runs,
/// unregisters the engine's login item (launchd stops it) and waits for it
/// to stop, removes the `xp` link if it points into this app, and, if
/// asked, deletes the data of the engine and the app and their Keychain
/// items. A step that fails does not stop the others, except that data is
/// never deleted under an engine that still runs. Then the app moves
/// itself to the Trash and quits.
class RemoveXPathBloc extends Bloc<RemoveXPathEvent, RemoveXPathState> {
  new({
    required this._engines,
    required this._agent,
    required this._linker,
    required this._data,
    required this._keychain,
    required this._app,
  }) : super(const RemoveXPathState()) {
    on<RemoveXPathConfirmed>(_onConfirmed, transformer: droppable());
    on<RemoveXPathTrashRequested>(_onTrash, transformer: droppable());
    on<RemoveXPathQuitRequested>(
      (event, emit) => _app.quit(),
      transformer: droppable(),
    );
  }

  final EnginesRepository _engines;
  final EngineAgent _agent;
  final CliLinker _linker;
  final DataWiper _data;
  final KeychainWiper _keychain;
  final RunningApp _app;

  Future<void> _onConfirmed(
    RemoveXPathConfirmed event,
    Emitter<RemoveXPathState> emit,
  ) async {
    emit(
      RemoveXPathState(
        phase: RemovalPhase.removing,
        steps: [
          for (final step in [
            RemovalStep.runners,
            RemovalStep.engine,
            RemovalStep.cli,
            if (event.deleteData) RemovalStep.data,
            if (event.deleteKeychain) RemovalStep.keychain,
          ])
            RemovalStepResult(step, RemovalStepState.pending),
        ],
      ),
    );

    Future<RemovalStepResult> run(
      RemovalStep step,
      Future<RemovalStepResult> Function() action,
    ) async {
      emit(state.withStep(RemovalStepResult(step, RemovalStepState.working)));
      RemovalStepResult result;
      try {
        result = await action();
      } on Exception catch (error) {
        result = RemovalStepResult(
          step,
          RemovalStepState.failed,
          detail: _describe(error),
        );
      }
      emit(state.withStep(result));
      return result;
    }

    await run(RemovalStep.runners, () async {
      final count = await _engines.revokeLocalRunners();
      return RemovalStepResult(
        RemovalStep.runners,
        RemovalStepState.done,
        count: count,
      );
    });
    final engine = await run(RemovalStep.engine, () async {
      await _agent.unregister();
      return RemovalStepResult(
        RemovalStep.engine,
        await _engines.waitForLocalEngineToStop()
            ? RemovalStepState.done
            : RemovalStepState.failed,
      );
    });
    await run(RemovalStep.cli, () async {
      final link = await _linker.unlink();
      return link.state == CliLinkState.failed
          ? RemovalStepResult(
              RemovalStep.cli,
              RemovalStepState.failed,
              detail: link.detail,
            )
          : const RemovalStepResult(RemovalStep.cli, RemovalStepState.done);
    });
    if (event.deleteData) {
      if (engine.state == RemovalStepState.done) {
        await run(RemovalStep.data, () async {
          await _data.wipe();
          return const RemovalStepResult(
            RemovalStep.data,
            RemovalStepState.done,
          );
        });
      } else {
        emit(
          state.withStep(
            const RemovalStepResult(RemovalStep.data, RemovalStepState.skipped),
          ),
        );
      }
    }
    if (event.deleteKeychain) {
      await run(RemovalStep.keychain, () async {
        final count = await _keychain.wipe();
        return RemovalStepResult(
          RemovalStep.keychain,
          RemovalStepState.done,
          count: count,
        );
      });
    }
    emit(RemoveXPathState(phase: RemovalPhase.removed, steps: state.steps));
  }

  Future<void> _onTrash(
    RemoveXPathTrashRequested event,
    Emitter<RemoveXPathState> emit,
  ) async {
    emit(RemoveXPathState(phase: RemovalPhase.leaving, steps: state.steps));
    if (await _app.moveToTrash()) {
      await _app.quit();
      return;
    }
    emit(RemoveXPathState(phase: RemovalPhase.trashFailed, steps: state.steps));
  }

  static String _describe(Exception error) => switch (error) {
    MacosServiceException(:final message) => message,
    _ => errorMessage(error),
  };
}

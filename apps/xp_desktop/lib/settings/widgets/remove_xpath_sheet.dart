import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/app/app_services.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/settings/bloc/remove_xpath_bloc.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';

/// The confirmation sheet of "Remove XPath", over the [RemoveXPathBloc] of
/// the settings page. It asks first ("Also delete engine data", "Also
/// delete Keychain items"); once confirmed it shows each step and cannot be
/// dismissed, and ends with moving the app to the Trash and quitting.
Future<void> showRemoveXPathSheet(BuildContext context) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  barrierColor: context.xpColors.scrimDefault,
  builder: (_) => MultiRepositoryProvider(
    providers: [RepositoryProvider.value(value: context.read<AppServices>())],
    child: BlocProvider.value(
      value: context.read<RemoveXPathBloc>(),
      child: const RemoveXPathSheet(),
    ),
  ),
);

class RemoveXPathSheet extends StatefulWidget {
  const new({super.key});

  @override
  State<RemoveXPathSheet> createState() => _RemoveXPathSheetState();
}

class _RemoveXPathSheetState extends State<RemoveXPathSheet> {
  var _deleteData = false;
  var _deleteKeychain = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final type = context.xpType;
    final state = context.watch<RemoveXPathBloc>().state;
    final bloc = context.read<RemoveXPathBloc>();
    final asking = state.phase == RemovalPhase.idle;
    final finished =
        state.phase == RemovalPhase.removed ||
        state.phase == RemovalPhase.leaving ||
        state.phase == RemovalPhase.trashFailed;
    final folders = context.read<AppServices>().dataWiper.folders;
    void close() => Navigator.of(context).pop();
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (asking) close();
        },
      },
      child: Shortcuts(
        // Return never removes anything.
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter):
              DoNothingAndStopPropagationIntent(),
        },
        child: Focus(
          autofocus: true,
          child: Dialog(
            backgroundColor: colors.surfaceOverlay,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(context.xpRadii.lg),
              side: BorderSide(color: colors.borderStrong),
            ),
            child: SizedBox(
              width: 560,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      finished ? l10n.removeDoneTitle : l10n.removeTitle,
                      style: type.headline.copyWith(color: colors.textPrimary),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      finished ? l10n.removeDoneBody : l10n.removeBody,
                      style: type.body.copyWith(color: colors.textSecondary),
                    ),
                    const SizedBox(height: 16),
                    if (asking) ...[
                      _Option(
                        label: l10n.removeDeleteData,
                        note: l10n.removeDeleteDataNote(folders.join(', ')),
                        selected: _deleteData,
                        onChanged: (on) => setState(() => _deleteData = on),
                      ),
                      const SizedBox(height: 10),
                      _Option(
                        label: l10n.removeDeleteKeychain,
                        note: l10n.removeDeleteKeychainNote,
                        selected: _deleteKeychain,
                        onChanged: (on) => setState(() => _deleteKeychain = on),
                      ),
                    ] else
                      for (final step in state.steps) _StepRow(step),
                    if (state.phase == RemovalPhase.trashFailed) ...[
                      const SizedBox(height: 12),
                      XpMessage(XpStatus.scanWarning, l10n.removeTrashFailed),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (asking) ...[
                          XpButton(
                            label: l10n.removeKeep,
                            size: XpButtonSize.large,
                            onPressed: close,
                          ),
                          const SizedBox(width: 8),
                          XpButton(
                            key: const Key('remove.confirm'),
                            label: l10n.removeConfirm,
                            kind: XpButtonKind.destructive,
                            size: XpButtonSize.large,
                            onPressed: () => bloc.add(
                              RemoveXPathConfirmed(
                                deleteData: _deleteData,
                                deleteKeychain: _deleteKeychain,
                              ),
                            ),
                          ),
                        ] else if (finished) ...[
                          XpButton(
                            key: const Key('remove.quit'),
                            label: l10n.removeQuit,
                            size: XpButtonSize.large,
                            onPressed: () =>
                                bloc.add(const RemoveXPathQuitRequested()),
                          ),
                          if (state.phase != RemovalPhase.trashFailed) ...[
                            const SizedBox(width: 8),
                            XpButton(
                              key: const Key('remove.trash'),
                              label: l10n.removeTrashAndQuit,
                              kind: XpButtonKind.primary,
                              size: XpButtonSize.large,
                              busy: state.phase == RemovalPhase.leaving,
                              onPressed: () =>
                                  bloc.add(const RemoveXPathTrashRequested()),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const new({
    required this.label,
    required this.note,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final String note;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      XpChip(
        label: label,
        icon: selected ? PhosphorIconsRegular.checkCircle : null,
        selected: selected,
        onChanged: onChanged,
      ),
      const SizedBox(height: 4),
      Text(
        note,
        style: context.xpType.caption.copyWith(
          color: context.xpColors.textSecondary,
        ),
      ),
    ],
  );
}

class _StepRow extends StatelessWidget {
  const new(this.result);

  final RemovalStepResult result;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final title = switch (result.step) {
      RemovalStep.runners => l10n.removeStepRunners,
      RemovalStep.engine => l10n.removeStepEngine,
      RemovalStep.cli => l10n.removeStepCli,
      RemovalStep.data => l10n.removeStepData,
      RemovalStep.keychain => l10n.removeStepKeychain,
    };
    final status = switch (result.state) {
      RemovalStepState.pending => XpStatus.jobQueued,
      RemovalStepState.working => XpStatus.jobRunning,
      RemovalStepState.done => XpStatus.jobSucceeded,
      RemovalStepState.skipped => XpStatus.jobSkipped,
      RemovalStepState.failed => XpStatus.jobFailed,
    };
    final detail = switch (result) {
      RemovalStepResult(:final String detail) => detail,
      RemovalStepResult(
        step: RemovalStep.runners,
        state: RemovalStepState.done,
        :final int count,
      ) =>
        l10n.removeRunnersRevoked(count),
      RemovalStepResult(
        step: RemovalStep.keychain,
        state: RemovalStepState.done,
        :final int count,
      ) =>
        l10n.removeKeychainDeleted(count),
      RemovalStepResult(
        step: RemovalStep.engine,
        state: RemovalStepState.failed,
      ) =>
        l10n.removeEngineStillRunning,
      RemovalStepResult(state: RemovalStepState.skipped) => l10n.removeDataKept,
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          XpStatusIcon(status),
          const SizedBox(width: 8),
          SizedBox(
            width: 180,
            child: Text(
              title,
              style: context.xpType.body.copyWith(color: colors.textPrimary),
            ),
          ),
          Expanded(
            child: Text(
              detail ?? '',
              style: context.xpType.caption.copyWith(
                color: result.state == RemovalStepState.failed
                    ? colors.onContainer(XpStatusPair.negative)
                    : colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

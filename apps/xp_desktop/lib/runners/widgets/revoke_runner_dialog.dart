import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';

/// Asks before revoking [runner]: what stops and what happens to its jobs.
/// `true` when the owner confirms; Return does nothing, Escape keeps it.
Future<bool> confirmRevokeRunner(BuildContext context, Runner runner) async =>
    await showDialog<bool>(
      context: context,
      barrierColor: context.xpColors.scrimDefault,
      builder: (_) => RevokeRunnerDialog(runner: runner),
    ) ??
    false;

class RevokeRunnerDialog extends StatelessWidget {
  const new({required this.runner, super.key});

  final Runner runner;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final type = context.xpType;
    void close({required bool confirmed}) =>
        Navigator.of(context).pop(confirmed);
    final points = [
      l10n.revokeRunnerCredential,
      if (runner.jobIds.isNotEmpty) l10n.revokeRunnerJobs(runner.jobIds.length),
      l10n.revokeRunnerName(runner.name),
    ];
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            close(confirmed: false),
      },
      child: Shortcuts(
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
              width: 460,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.revokeRunnerTitle(runner.name),
                      style: type.headline.copyWith(color: colors.textPrimary),
                    ),
                    const SizedBox(height: 14),
                    for (final point in points)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          '•  $point',
                          style: type.body.copyWith(color: colors.textPrimary),
                        ),
                      ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        XpButton(
                          label: l10n.revokeRunnerKeep,
                          size: XpButtonSize.large,
                          onPressed: () => close(confirmed: false),
                        ),
                        const SizedBox(width: 8),
                        XpButton(
                          label: l10n.revokeRunnerConfirm,
                          kind: XpButtonKind.destructive,
                          size: XpButtonSize.large,
                          onPressed: () => close(confirmed: true),
                        ),
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

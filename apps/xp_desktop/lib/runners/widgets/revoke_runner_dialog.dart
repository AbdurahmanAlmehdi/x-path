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
    return XpConfirmDialog(
      title: l10n.revokeRunnerTitle(runner.name),
      points: [
        l10n.revokeRunnerCredential,
        if (runner.jobIds.isNotEmpty)
          l10n.revokeRunnerJobs(runner.jobIds.length),
        l10n.revokeRunnerName(runner.name),
      ],
      keep: l10n.revokeRunnerKeep,
      confirm: l10n.revokeRunnerConfirm,
    );
  }
}

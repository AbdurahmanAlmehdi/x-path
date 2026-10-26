import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/job/widgets/job_status.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/shell/cubit/shell_cubit.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';

/// One run in a list: its state, workflow, flavors and platforms, version
/// and when it was dispatched. It opens the run's job view.
class RunRow extends StatelessWidget {
  const new({required this.run, required this.workflowName, super.key});

  final Run run;

  /// What its workflow is called; its id when it is not known.
  final String? workflowName;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final type = context.xpType;
    final request = run.request;
    final scope = [...?request?.flavors, ...?request?.platforms].join(' · ');
    void open() => context.read<ShellCubit>().show(
      JobDestination(run.id, projectId: run.projectId),
    );
    return XpTappable(
      onTap: open,
      radius: 0,
      onSecondaryTap: (position) => showXpContextMenu(context, position, [
        XpMenuAction(l10n.menuOpenJob, open),
        XpMenuAction.copy(l10n.menuCopySha, run.sha),
        if (run.version case final version?)
          XpMenuAction.copy(
            l10n.menuCopyVersion,
            versionLabel(version, run.build),
          ),
      ]),
      child: SizedBox(
        height: context.xpSizes.rowDefault,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              XpStatusIcon(runStatus(run.state)),
              const SizedBox(width: 8),
              ConstrainedBox(
                // Grows with the text size (U6c).
                constraints: const BoxConstraints(minWidth: 120),
                child: Text(
                  l10n.runState(run.state),
                  style: type.body.copyWith(color: colors.textSecondary),
                ),
              ),
              Expanded(
                child: Text(
                  workflowName ?? run.workflowId,
                  overflow: TextOverflow.ellipsis,
                  style: type.bodyStrong.copyWith(color: colors.textPrimary),
                ),
              ),
              if (scope.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  scope,
                  style: type.code.copyWith(color: colors.textSecondary),
                ),
              ],
              if (run.version case final version?) ...[
                const SizedBox(width: 12),
                Text(
                  versionLabel(version, run.build),
                  style: type.code.copyWith(color: colors.textPrimary),
                ),
              ],
              const SizedBox(width: 12),
              SizedBox(
                width: 120,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: XpTime(
                    run.createdAt,
                    style: type.caption.copyWith(color: colors.textSecondary),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/approvals/bloc/pending_approvals_bloc.dart';
import 'package:xp_desktop/approvals/view/approval_review_sheet.dart';
import 'package:xp_desktop/approvals/widgets/approval_labels.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/shell/cubit/shell_cubit.dart';
import 'package:xp_desktop/shell/widgets/shell_page.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';

/// The needs-you bar (`Main.dc.html`, `Release-A-Lanes.dc.html`): the
/// approval of [projectId] that expires first, with "Review…" (⇧⌘A), which
/// opens the confirmation sheet, and "Deny…". Nothing when nothing waits.
class NeedsYouBar extends StatelessWidget {
  const new({required this.projectId, super.key});

  final String projectId;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final type = context.xpType;
    final waiting = context.watch<PendingApprovalsBloc>().state.of(projectId);
    if (waiting.isEmpty) return const SizedBox.shrink();
    final approval = waiting.first;
    final now = XpClock.wall(context);
    final ink = colors.statusAttentionOnContainer;
    final canCommand = context.canCommand;
    return Semantics(
      container: true,
      label: l10n.needsYou,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: colors.statusAttentionContainer,
          border: Border(bottom: BorderSide(color: colors.borderDefault)),
        ),
        child: Row(
          children: [
            XpSectionLabel(l10n.needsYou, color: ink),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                l10n.approvalTitle(approval),
                overflow: TextOverflow.ellipsis,
                style: type.bodyStrong.copyWith(color: ink),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              l10n.needsYouMeta(
                shortSha(approval.sha),
                formatCountdown(approval.expiresAt, now),
              ),
              style: type.caption.copyWith(
                color: expiresSoon(approval, now)
                    ? colors.statusCautionOnContainer
                    : ink,
              ),
            ),
            if (waiting.length > 1) ...[
              const SizedBox(width: 10),
              XpButton(
                label: l10n.needsYouMore(waiting.length - 1),
                kind: XpButtonKind.tertiary,
                size: XpButtonSize.small,
                onPressed: () => context.read<ShellCubit>().show(
                  const ApprovalsDestination(),
                ),
              ),
            ],
            const Spacer(),
            XpButton(
              label: l10n.approvalReview,
              hint: '⇧⌘A',
              kind: XpButtonKind.warning,
              onPressed: () => showApprovalReview(context, approval.id),
            ),
            const SizedBox(width: 8),
            XpButton(
              label: l10n.approvalDenyEllipsis,
              tooltip: canCommand ? null : l10n.readOnlyHint,
              onPressed: canCommand
                  ? () => showApprovalReview(context, approval.id, deny: true)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

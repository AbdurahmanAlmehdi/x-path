import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/approvals/bloc/approvals_inbox_bloc.dart';
import 'package:xp_desktop/approvals/view/approval_review_sheet.dart';
import 'package:xp_desktop/approvals/widgets/approval_details.dart';
import 'package:xp_desktop/approvals/widgets/approval_labels.dart';
import 'package:xp_desktop/job/widgets/job_status.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/projects/bloc/projects_bloc.dart';
import 'package:xp_desktop/shell/widgets/shell_page.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';
import 'package:xp_repositories/xp_repositories.dart';

/// The approvals inbox (`Approvals-Inbox.dc.html`), showing [approvalId]
/// first if given.
class ApprovalsPage extends StatelessWidget {
  const new({this.approvalId, super.key});

  final String? approvalId;

  @override
  Widget build(BuildContext context) => BlocProvider(
    key: ValueKey(approvalId),
    create: (context) => ApprovalsInboxBloc(
      approvals: context.read<ApprovalsRepository>(),
      jobs: context.read<JobsRepository>(),
      releases: context.read<ReleasesRepository>(),
    )..add(ApprovalsInboxSubscriptionRequested(approvalId: approvalId)),
    child: const ApprovalsView(),
  );
}

class ApprovalsView extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = context.watch<ApprovalsInboxBloc>().state;
    final bloc = context.read<ApprovalsInboxBloc>();
    final selected = state.selected;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(
          LogicalKeyboardKey.keyA,
          meta: true,
          shift: true,
        ): () {
          if (selected != null && selected.state == ApprovalState.pending) {
            unawaited(showApprovalReview(context, selected.id));
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: ShellPage(
          title: l10n.approvalsTitle,
          cached: state.cached,
          subtitle: l10n.approvalsSubtitle(
            context.engineName,
            state.pendingCount,
          ),
          actions: [
            XpSegmented<ApprovalsFilter>(
              value: state.filter,
              values: ApprovalsFilter.values,
              labelOf: (filter) => switch (filter) {
                ApprovalsFilter.pending => l10n.approvalsPending,
                ApprovalsFilter.decided => l10n.approvalsDecided,
                ApprovalsFilter.expired => l10n.approvalsExpired,
              },
              onChanged: (filter) =>
                  bloc.add(ApprovalsInboxFilterChanged(filter)),
            ),
          ],
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 340, child: _List(state)),
              const XpHairline(vertical: true),
              Expanded(
                child: selected == null
                    ? _Empty(state)
                    : _Detail(approval: selected, state: state),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _List extends StatelessWidget {
  const new(this.state);

  final ApprovalsInboxState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final visible = state.visible;
    final caption = switch (state.filter) {
      ApprovalsFilter.pending => l10n.approvalsPending,
      ApprovalsFilter.decided => l10n.approvalsDecided,
      ApprovalsFilter.expired => l10n.approvalsExpired,
    };
    return ColoredBox(
      color: context.xpColors.surfaceBase,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
            child: XpSectionLabel('$caption · ${visible.length}'),
          ),
          if (state.error case final error?)
            Padding(
              padding: const EdgeInsets.all(4),
              child: XpErrorState(
                error,
                onRetry: () => context.read<ApprovalsInboxBloc>().add(
                  ApprovalsInboxSubscriptionRequested(
                    approvalId: state.selectedId,
                  ),
                ),
              ),
            )
          else if (!state.loaded)
            const Padding(
              padding: EdgeInsets.all(4),
              child: XpLoading(rows: 3),
            ),
          for (final approval in visible)
            _Row(
              approval: approval,
              selected: approval.id == state.selected?.id,
            ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const new({required this.approval, required this.selected});

  final Approval approval;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final type = context.xpType;
    final project = context.watch<ProjectsBloc>().state.byId(
      approval.projectId,
    );
    final now = XpClock.wall(context);
    return Semantics(
      button: true,
      selected: selected,
      label: l10n.approvalTitle(approval),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => context.read<ApprovalsInboxBloc>().add(
            ApprovalsInboxApprovalSelected(approval.id),
          ),
          child: Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: selected ? colors.surfaceSelected : null,
              borderRadius: BorderRadius.circular(context.xpRadii.md),
              border: Border.all(
                color: selected ? colors.borderStrong : Colors.transparent,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    XpStatusIcon(approvalStatus(approval.state)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.approvalTitle(approval),
                        overflow: TextOverflow.ellipsis,
                        style: type.bodyStrong.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    XpTime(
                      approval.createdAt,
                      style: type.code.copyWith(color: colors.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    project?.fullName.split('/').last ?? approval.projectId,
                    l10n.gateAction(approval.action),
                    shortSha(approval.sha),
                  ].join(' · '),
                  overflow: TextOverflow.ellipsis,
                  style: type.caption.copyWith(color: colors.textSecondary),
                ),
                if (approval.state == ApprovalState.pending) ...[
                  const SizedBox(height: 2),
                  Text(
                    l10n.approvalExpiresShort(
                      formatCountdown(approval.expiresAt, now),
                    ),
                    style: type.caption.copyWith(
                      color: expiresSoon(approval, now)
                          ? colors.statusCautionOnContainer
                          : colors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const new(this.state);

  final ApprovalsInboxState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    if (!state.loaded) return const SizedBox();
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            PhosphorIconsRegular.checkCircle,
            size: context.xpSizes.iconXl,
            color: colors.textTertiary,
          ),
          const SizedBox(height: 12),
          Text(
            state.filter == ApprovalsFilter.pending
                ? l10n.approvalsNothingWaits
                : l10n.approvalsNone,
            style: context.xpType.title.copyWith(color: colors.textPrimary),
          ),
        ],
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const new({required this.approval, required this.state});

  final Approval approval;
  final ApprovalsInboxState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final pending = approval.state == ApprovalState.pending;
    final canCommand = context.canCommand;
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
      children: [
        ApprovalStateLine(approval),
        const SizedBox(height: 14),
        ApprovalHero(approval),
        const SizedBox(height: 6),
        Text(
          l10n.approvalAskedAt(formatTime(approval.createdAt)),
          style: context.xpType.caption.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: 18),
        ApprovalDetails(approval: approval, subject: state.subject),
        if (pending) ...[
          const SizedBox(height: 18),
          ApprovalConsequence(approval: approval, subject: state.subject),
          const SizedBox(height: 18),
          Row(
            children: [
              XpButton(
                label: l10n.approvalDenyEllipsis,
                size: XpButtonSize.large,
                tooltip: canCommand ? null : l10n.readOnlyHint,
                onPressed: canCommand
                    ? () => showApprovalReview(context, approval.id, deny: true)
                    : null,
              ),
              const SizedBox(width: 8),
              XpButton(
                label: l10n.approvalApproveEllipsis,
                hint: '⇧⌘A',
                kind: XpButtonKind.primary,
                size: XpButtonSize.large,
                tooltip: canCommand ? null : l10n.readOnlyHint,
                onPressed: canCommand
                    ? () => showApprovalReview(context, approval.id)
                    : null,
              ),
            ],
          ),
        ],
      ],
    );
  }
}

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart' hide StepState;
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/approvals/bloc/approval_subject.dart';
import 'package:xp_desktop/approvals/widgets/approval_labels.dart';
import 'package:xp_desktop/job/widgets/job_status.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/projects/bloc/projects_bloc.dart';
import 'package:xp_desktop/shell/cubit/shell_cubit.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';

/// The flavor [release] builds, as the scan of [project] describes it.
FlavorProfile? flavorOf(Project? project, Release? release) {
  if (project == null || release == null) return null;
  for (final app in project.profile.apps) {
    if (app.path != release.app) continue;
    for (final flavor in app.flavors) {
      if (flavor.name == release.flavor) return flavor;
    }
  }
  return null;
}

/// The hero of an approval: its icon and what it asks for.
class ApprovalHero extends StatelessWidget {
  const new(this.approval, {super.key});

  final Approval approval;

  @override
  Widget build(BuildContext context) {
    final status = approvalStatus(approval.state);
    return Row(
      children: [
        XpStatusIcon(status, size: context.xpSizes.iconLg),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            context.l10n.approvalTitle(approval),
            style: context.xpType.hero.copyWith(
              color: context.xpColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

/// The state of an approval as a badge, with its countdown while it waits
/// or who decided it.
class ApprovalStateLine extends StatelessWidget {
  const new(this.approval, {super.key});

  final Approval approval;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final now = XpClock.now(context);
    final soon = expiresSoon(approval, now);
    final text = switch (approval.state) {
      ApprovalState.pending => l10n.approvalExpiresIn(
        formatCountdown(approval.expiresAt, now),
        formatDateTime(approval.createdAt),
      ),
      ApprovalState.expired => l10n.approvalExpiredAt(
        formatDateTime(approval.decidedAt ?? approval.expiresAt),
      ),
      _ => l10n.approvalDecidedBy(
        approval.decidedBy?.name ?? l10n.approvalSomeone,
        formatDateTime(approval.decidedAt ?? approval.createdAt),
      ),
    };
    return Row(
      children: [
        XpBadge(
          approvalStatus(approval.state),
          l10n.approvalState(approval.state),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: context.xpType.caption.copyWith(
              color: approval.state == ApprovalState.pending && soon
                  ? colors.statusCautionOnContainer
                  : colors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// What an approval is bound to (`Approvals-Inbox.dc.html`): project,
/// flavor, version, commit, the job that waits and the gate.
class ApprovalDetails extends StatelessWidget {
  const new({required this.approval, required this.subject, super.key});

  final Approval approval;
  final ApprovalSubject subject;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final type = context.xpType;
    final project = context.watch<ProjectsBloc>().state.byId(
      approval.projectId,
    );
    final release = subject.release;
    final job = subject.job;
    final flavor = flavorOf(project, release);
    final app = project?.profile.apps
        .where((app) => app.path == release?.app)
        .firstOrNull;
    final waiting = job?.steps
        .where((step) => step.state == StepState.waitingForApproval)
        .firstOrNull;
    final rows = <(String, Widget)>[
      (
        l10n.approvalProject,
        Text(
          [
            project?.fullName.split('/').last ?? approval.projectId,
            ?app?.name,
          ].join(' · '),
          style: type.body.copyWith(color: colors.textPrimary),
        ),
      ),
      if (release != null)
        (
          l10n.approvalFlavor,
          Row(
            children: [
              Text(
                release.flavor,
                style: type.bodyStrong.copyWith(color: colors.textPrimary),
              ),
              if (flavor?.iosBundleId ?? flavor?.androidAppId
                  case final bundleId?) ...[
                Text(
                  ' · ',
                  style: type.body.copyWith(color: colors.textSecondary),
                ),
                Flexible(child: XpCode(bundleId)),
              ],
            ],
          ),
        ),
      if (approval.version case final version?)
        (l10n.approvalVersion, XpCode(pubspecLabel(version))),
      (
        l10n.approvalCommit,
        XpSha(
          approval.sha,
          style: context.xpType.code.copyWith(
            color: context.xpColors.textPrimary,
          ),
        ),
      ),
      if (job != null)
        (
          l10n.approvalJob,
          Row(
            children: [
              Flexible(
                child: _Link(
                  job.name ?? job.id,
                  onTap: job.runId == null
                      ? null
                      : () {
                          Navigator.of(context).maybePop();
                          context.read<ShellCubit>().show(
                            JobDestination(
                              job.runId!,
                              jobId: job.id,
                              projectId: job.projectId,
                            ),
                          );
                        },
                ),
              ),
              if (waiting != null && approval.state == ApprovalState.pending)
                Text(
                  ' · ${l10n.approvalWaits(l10n.stepKind(waiting.kind))}',
                  style: type.body.copyWith(color: colors.textSecondary),
                ),
            ],
          ),
        ),
      (
        l10n.approvalGate,
        Text(
          l10n.approvalGateName(l10n.gateAction(approval.action)),
          style: type.body.copyWith(color: colors.textSecondary),
        ),
      ),
      if (approval.reason case final reason?)
        (
          l10n.approvalReason,
          Text(reason, style: type.body.copyWith(color: colors.textPrimary)),
        ),
    ];
    return XpPanel(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, (label, value)) in rows.indexed) ...[
            if (index > 0) const SizedBox(height: 8),
            Row(
              children: [
                SizedBox(
                  width: 96,
                  child: Text(
                    label,
                    style: type.caption.copyWith(color: colors.textSecondary),
                  ),
                ),
                Expanded(child: value),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// "If you approve…": what approving does, and that the approval is void if
/// what it is bound to changes (DECISIONS.md).
class ApprovalConsequence extends StatelessWidget {
  const new({required this.approval, required this.subject, super.key});

  final Approval approval;
  final ApprovalSubject subject;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final project = context.watch<ProjectsBloc>().state.byId(
      approval.projectId,
    );
    final release = subject.release;
    final flavor = flavorOf(project, release);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        XpSectionLabel(l10n.approvalIfYouApprove),
        const SizedBox(height: 6),
        Text(
          l10n.approvalConsequence(
            approval,
            flavor: release?.flavor,
            bundleId: flavor?.iosBundleId ?? flavor?.androidAppId,
            baseBranch: release?.baseBranch ?? project?.defaultBaseBranch,
          ),
          style: context.xpType.body.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.approvalVoid,
          style: context.xpType.caption.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}

class _Link extends StatelessWidget {
  const new(this.label, {this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final style = context.xpType.body.copyWith(
      color: onTap == null
          ? context.xpColors.textPrimary
          : context.xpColors.textLink,
    );
    final text = Text(label, overflow: TextOverflow.ellipsis, style: style);
    if (onTap == null) return text;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: text),
    );
  }
}

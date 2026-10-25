import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/app/bloc/engine_connection_bloc.dart';
import 'package:xp_desktop/approvals/bloc/approval_review_bloc.dart';
import 'package:xp_desktop/approvals/widgets/approval_details.dart';
import 'package:xp_desktop/approvals/widgets/approval_labels.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/shell/widgets/shell_page.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';
import 'package:xp_repositories/xp_repositories.dart';

/// Opens the confirmation sheet of [approvalId] in the main window: the only
/// place the app approves or denies (DECISIONS.md). [deny] opens it at the
/// denial.
Future<void> showApprovalReview(
  BuildContext context,
  String approvalId, {
  bool deny = false,
}) {
  final approvals = context.read<ApprovalsRepository>();
  final jobs = context.read<JobsRepository>();
  final releases = context.read<ReleasesRepository>();
  return showDialog<void>(
    context: context,
    barrierColor: context.xpColors.scrimDefault,
    builder: (_) => BlocProvider(
      create: (_) => ApprovalReviewBloc(
        approvals: approvals,
        jobs: jobs,
        releases: releases,
      )..add(ApprovalReviewStarted(approvalId)),
      child: ApprovalReviewSheet(deny: deny),
    ),
  );
}

/// The confirmation sheet: what the approval is bound to, "If you approve…",
/// and Approve, which only ⌘↩ (or a click) triggers once the arming delay is
/// over. Return never approves.
class ApprovalReviewSheet extends StatefulWidget {
  const new({this.deny = false, super.key});

  /// Whether the sheet opens at the denial.
  final bool deny;

  @override
  State<ApprovalReviewSheet> createState() => _ApprovalReviewSheetState();
}

class _ApprovalReviewSheetState extends State<ApprovalReviewSheet> {
  late bool _denying = widget.deny;
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  bool get _canCommand =>
      context.read<EngineConnectionBloc>().state.status.canCommand;

  void _approve() {
    if (!_canCommand) return;
    context.read<ApprovalReviewBloc>().add(
      const ApprovalReviewApproveRequested(),
    );
  }

  void _deny() {
    if (!_canCommand) return;
    context.read<ApprovalReviewBloc>().add(
      ApprovalReviewDenyRequested(reason: _reason.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.xpColors;
    final state = context.watch<ApprovalReviewBloc>().state;
    final approval = state.approval;
    return BlocListener<ApprovalReviewBloc, ApprovalReviewState>(
      listenWhen: (previous, current) =>
          current.status != previous.status &&
          (current.status == ApprovalReviewStatus.approved ||
              current.status == ApprovalReviewStatus.denied),
      listener: (context, _) => Navigator.of(context).pop(),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.enter, meta: true): () {
            if (!_denying) _approve();
          },
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              Navigator.of(context).pop(),
        },
        child: Shortcuts(
          // Return never approves, not even with the button focused.
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.enter):
                DoNothingAndStopPropagationIntent(),
            SingleActivator(LogicalKeyboardKey.numpadEnter):
                DoNothingAndStopPropagationIntent(),
          },
          child: Focus(
            autofocus: true,
            child: Dialog(
              alignment: Alignment.topCenter,
              insetPadding: const EdgeInsets.only(top: 36),
              backgroundColor: colors.surfaceOverlay,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(context.xpRadii.lg),
                side: BorderSide(color: colors.borderStrong),
              ),
              child: SizedBox(
                width: 600,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                        child: approval == null
                            ? _Loading(state)
                            : _Body(
                                state: state,
                                denying: _denying,
                                reason: _reason,
                              ),
                      ),
                    ),
                    _Footer(
                      state: state,
                      denying: _denying,
                      onApprove: _approve,
                      onDeny: () => setState(() => _denying = true),
                      onBack: () => setState(() => _denying = false),
                      onConfirmDeny: _deny,
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

class _Loading extends StatelessWidget {
  const new(this.state);

  final ApprovalReviewState state;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 120,
    child: Center(
      child: state.status == ApprovalReviewStatus.failed
          ? XpMessage(
              XpStatus.scanError,
              state.error ?? context.l10n.approvalGone,
            )
          : const XpStatusIcon(XpStatus.jobRunning),
    ),
  );
}

class _Body extends StatelessWidget {
  const new({required this.state, required this.denying, required this.reason});

  final ApprovalReviewState state;
  final bool denying;
  final TextEditingController reason;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final approval = state.approval!;
    final settled = state.status == ApprovalReviewStatus.alreadyDecided;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ApprovalStateLine(approval),
        const SizedBox(height: 12),
        ApprovalHero(approval),
        const SizedBox(height: 4),
        Text(
          l10n.approvalAskedAt(formatTime(approval.createdAt)),
          style: context.xpType.caption.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: 16),
        if (settled) ...[
          XpMessage(
            approvalStatus(approval.state),
            approval.state == ApprovalState.expired
                ? l10n.approvalExpiredElsewhere
                : l10n.approvalDecidedElsewhere(
                    l10n.approvalState(approval.state).toLowerCase(),
                    approval.decidedBy?.name ?? l10n.approvalSomeone,
                  ),
          ),
          const SizedBox(height: 16),
        ],
        ApprovalDetails(approval: approval, subject: state.subject),
        if (!settled) ...[
          const SizedBox(height: 16),
          ApprovalConsequence(approval: approval, subject: state.subject),
        ],
        if (denying && !settled) ...[
          const SizedBox(height: 16),
          XpTextField(
            label: l10n.approvalDenyReason,
            hint: l10n.approvalDenyReasonHint,
            controller: reason,
          ),
        ],
        if (state.error case final error? when !settled) ...[
          const SizedBox(height: 12),
          XpMessage.error(error),
        ],
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const new({
    required this.state,
    required this.denying,
    required this.onApprove,
    required this.onDeny,
    required this.onBack,
    required this.onConfirmDeny,
  });

  final ApprovalReviewState state;
  final bool denying;
  final VoidCallback onApprove;
  final VoidCallback onDeny;
  final VoidCallback onBack;
  final VoidCallback onConfirmDeny;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final canCommand = context.canCommand;
    final open =
        state.approval != null &&
        state.status != ApprovalReviewStatus.alreadyDecided &&
        state.status != ApprovalReviewStatus.failed;
    final close = XpButton(
      label: open ? l10n.approvalCancel : l10n.approvalClose,
      size: XpButtonSize.large,
      onPressed: () => Navigator.of(context).pop(),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.borderDefault)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              open && !denying ? l10n.approvalReturnHint : '',
              style: context.xpType.caption.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
          if (!open)
            close
          else if (denying) ...[
            XpButton(
              label: l10n.approvalBack,
              size: XpButtonSize.large,
              onPressed: onBack,
            ),
            const SizedBox(width: 8),
            XpButton(
              label: l10n.approvalDeny,
              kind: XpButtonKind.destructive,
              size: XpButtonSize.large,
              busy: state.status == ApprovalReviewStatus.denying,
              tooltip: canCommand ? null : l10n.readOnlyHint,
              onPressed: state.canDeny && canCommand ? onConfirmDeny : null,
            ),
          ] else ...[
            close,
            const SizedBox(width: 8),
            XpButton(
              label: l10n.approvalDenyEllipsis,
              size: XpButtonSize.large,
              onPressed: state.canDeny && canCommand ? onDeny : null,
            ),
            const SizedBox(width: 8),
            XpButton(
              label: l10n.approvalApprove,
              hint: '⌘↩',
              kind: XpButtonKind.primary,
              size: XpButtonSize.large,
              busy: state.status == ApprovalReviewStatus.approving,
              tooltip: !canCommand
                  ? l10n.readOnlyHint
                  : state.armed
                  ? null
                  : l10n.approvalArming,
              onPressed: state.canApprove && canCommand ? onApprove : null,
            ),
          ],
        ],
      ),
    );
  }
}

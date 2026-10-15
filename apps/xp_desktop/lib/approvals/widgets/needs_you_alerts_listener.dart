import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/app/app_services.dart';
import 'package:xp_desktop/approvals/bloc/pending_approvals_bloc.dart';
import 'package:xp_desktop/approvals/view/approval_review_sheet.dart';
import 'package:xp_desktop/approvals/widgets/approval_labels.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/projects/bloc/projects_bloc.dart';
import 'package:xp_desktop/shell/cubit/shell_cubit.dart';
import 'package:xp_desktop/widgets/widgets.dart';
import 'package:xp_macos_services/xp_macos_services.dart';

/// Tells the owner about approvals when they are not looking at the window:
/// a macOS notification for each approval that starts waiting while the app
/// runs, and the menu bar extra with every approval that waits. Their
/// "Review…" opens the confirmation sheet here, in the main window; neither
/// approves anything.
class NeedsYouAlertsListener extends StatefulWidget {
  const new({required this.child, super.key});

  final Widget child;

  @override
  State<NeedsYouAlertsListener> createState() => _NeedsYouAlertsListenerState();
}

class _NeedsYouAlertsListenerState extends State<NeedsYouAlertsListener> {
  late final NeedsYouAlerts _alerts = context.read<AppServices>().alerts;
  late final StreamSubscription<NeedsYouAction> _actions;

  /// The approvals the engine said wait, once it said so; `null` before.
  Set<String>? _known;

  @override
  void initState() {
    super.initState();
    _actions = _alerts.actions.listen(_onAction);
  }

  @override
  void dispose() {
    unawaited(_actions.cancel());
    super.dispose();
  }

  void _onAction(NeedsYouAction action) {
    if (!mounted) return;
    switch (action) {
      case ReviewApproval(:final approvalId):
        unawaited(showApprovalReview(context, approvalId));
      case ShowApproval(:final approvalId):
        context.read<ShellCubit>().show(
          ApprovalsDestination(approvalId: approvalId),
        );
      case OpenApp():
        // The runner brought the window forward.
        break;
    }
  }

  String _where(Approval approval) {
    final project = context.read<ProjectsBloc>().state.byId(approval.projectId);
    return [
      project?.fullName.split('/').last ?? approval.projectId,
      shortSha(approval.sha),
    ].join(' · ');
  }

  void _onPending(PendingApprovalsState state) {
    if (!state.loaded) return;
    final l10n = context.l10n;
    final now = DateTime.now();
    unawaited(
      _alerts.updateMenuBar(
        MenuBarContent(
          tooltip: state.approvals.isEmpty
              ? l10n.appTitle
              : l10n.menuBarTooltip(state.approvals.length),
          header: state.approvals.isEmpty
              ? l10n.menuBarNothing
              : l10n.menuBarNeedsYou(state.approvals.length),
          items: [
            for (final approval in state.approvals)
              MenuBarItem(
                approvalId: approval.id,
                title: l10n.menuBarReview(l10n.approvalTitle(approval)),
                detail: l10n.menuBarLeft(
                  _where(approval),
                  formatCountdown(approval.expiresAt, now),
                ),
              ),
          ],
          openApp: l10n.menuBarOpen,
        ),
      ),
    );
    if (state.cached) return;
    final ids = {for (final approval in state.approvals) approval.id};
    final known = _known;
    _known = ids;
    // What waited before the engine first answered was there before this
    // window: it is in the menu bar and the inbox, not notified again.
    if (known == null) return;
    for (final approval in state.approvals) {
      if (known.contains(approval.id)) continue;
      unawaited(
        _alerts.notify(
          ApprovalNotice(
            approvalId: approval.id,
            title: l10n.approvalTitle(approval),
            body: l10n.notificationBody(
              _where(approval),
              formatCountdown(approval.expiresAt, now),
            ),
            review: l10n.approvalReview,
            later: l10n.notificationLater,
          ),
        ),
      );
    }
    for (final id in known.difference(ids)) {
      unawaited(_alerts.withdraw(id));
    }
  }

  @override
  Widget build(BuildContext context) =>
      BlocListener<PendingApprovalsBloc, PendingApprovalsState>(
        listener: (context, state) => _onPending(state),
        child: widget.child,
      );
}

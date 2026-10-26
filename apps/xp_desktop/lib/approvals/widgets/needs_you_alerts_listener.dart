import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/app/app_services.dart';
import 'package:xp_desktop/app/bloc/engine_notices_bloc.dart';
import 'package:xp_desktop/approvals/bloc/pending_approvals_bloc.dart';
import 'package:xp_desktop/approvals/view/approval_review_sheet.dart';
import 'package:xp_desktop/approvals/widgets/approval_labels.dart';
import 'package:xp_desktop/dispatch/view/dispatch_sheet.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/projects/bloc/projects_bloc.dart';
import 'package:xp_desktop/shell/cubit/shell_cubit.dart';
import 'package:xp_desktop/widgets/widgets.dart';
import 'package:xp_macos_services/xp_macos_services.dart';
import 'package:xp_repositories/xp_repositories.dart';

/// Tells the owner what happens when they are not looking at the window: a
/// macOS notification for each approval that starts waiting while the app
/// runs and for each engine notice not turned off in Settings (U6b), and the
/// menu bar extra with every approval that waits, the runs that work and
/// quick dispatch. Their "Review…" opens the confirmation sheet here, in the
/// main window; neither approves anything.
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
      case ShowNotice(:final target):
        unawaited(openNoticeTarget(context, target));
      case DispatchProject(:final projectId):
        if (context.read<ProjectsBloc>().state.byId(projectId)
            case final project?) {
          unawaited(dispatchFor(context, project));
        }
      case OpenApp():
        // The runner brought the window forward.
        break;
    }
  }

  /// Shows [notice] unless the owner turned its kind off.
  void _onNotice(Notice notice) {
    final preferences = context.read<AppServices>().preferences;
    if (preferences.mutedNotices.contains(notice.kind.name)) return;
    final l10n = context.l10n;
    final (title, body) = switch (notice) {
      EngineRaisedNotice(:final event) => (event.title, event.body),
      RunnerLostNotice(:final event) => (
        l10n.noticeRunnerLost,
        l10n.noticeRunnerLostBody(event.state.wire),
      ),
      CapabilityLostNotice(:final runner, :final lost) => (
        l10n.noticeCapabilityLostTitle(runner, lost.join(', ')),
        l10n.noticeCapabilityLostBody,
      ),
      JobWaitingNotice(:final jobName, :final reason) => (
        l10n.noticeJobWaiting,
        l10n.noticeJobWaitingBody(jobName, reason),
      ),
    };
    unawaited(
      _alerts.notifyNotice(
        EngineNotice(target: notice.target, title: title, body: body),
      ),
    );
  }

  String _where(Approval approval) {
    final project = context.read<ProjectsBloc>().state.byId(approval.projectId);
    return [
      project?.fullName.split('/').last ?? approval.projectId,
      shortSha(approval.sha),
    ].join(' · ');
  }

  void _updateMenuBar() {
    final l10n = context.l10n;
    final now = DateTime.now();
    final state = context.read<PendingApprovalsBloc>().state;
    final running = context.read<EngineNoticesBloc>().state.running;
    final projects = context.read<ProjectsBloc>().state;
    String name(String projectId) =>
        projects.byId(projectId)?.fullName.split('/').last ?? projectId;
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
          runningHeader: running.isEmpty
              ? null
              : l10n.menuBarRunning(running.length),
          running: [
            for (final run in running)
              MenuBarRun(
                target: 'run:${run.id}:${run.projectId}',
                title: l10n.menuBarRunTitle(
                  name(run.projectId),
                  run.version ?? shortSha(run.sha),
                ),
                detail: l10n.menuBarRunDetail(
                  name(run.projectId),
                  run.jobs.where((job) => job.state.isFinished).length,
                  run.jobs.length,
                ),
              ),
          ],
          dispatch: l10n.menuBarDispatch,
          projects: [
            for (final project in projects.projects)
              MenuBarProject(projectId: project.id, name: project.fullName),
          ],
        ),
      ),
    );
  }

  void _onPending(PendingApprovalsState state) {
    if (!state.loaded) return;
    _updateMenuBar();
    final l10n = context.l10n;
    final now = DateTime.now();
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
  Widget build(BuildContext context) => MultiBlocListener(
    listeners: [
      BlocListener<PendingApprovalsBloc, PendingApprovalsState>(
        listener: (context, state) => _onPending(state),
      ),
      BlocListener<EngineNoticesBloc, EngineNoticesState>(
        listenWhen: (previous, current) => previous.count != current.count,
        listener: (context, state) => _onNotice(state.notice!),
      ),
      BlocListener<EngineNoticesBloc, EngineNoticesState>(
        listenWhen: (previous, current) => previous.running != current.running,
        listener: (context, state) => _updateMenuBar(),
      ),
    ],
    child: widget.child,
  );
}

/// Opens what a notice or a run of the menu bar names (see [Notice.target]).
Future<void> openNoticeTarget(BuildContext context, String target) async {
  final shell = context.read<ShellCubit>();
  switch (target.split(':')) {
    case ['job', final jobId]:
      try {
        final job =
            (await context.read<JobsRepository>().watchJob(jobId).first).value;
        if (job.runId case final runId?) {
          shell.show(
            JobDestination(runId, jobId: job.id, projectId: job.projectId),
          );
        }
      } on Exception {
        // The job is gone: there is nothing to open.
      }
    case ['run', final runId, final projectId, ...final job]:
      shell.show(
        JobDestination(runId, jobId: job.firstOrNull, projectId: projectId),
      );
    case ['release', final projectId, final releaseId]:
      shell.show(ReleasesDestination(projectId, releaseId: releaseId));
    case ['credentials', final projectId]:
      shell.show(CredentialsDestination(projectId));
    case ['runners']:
      shell.show(const RunnersDestination());
    default:
      shell.show(const SettingsDestination());
  }
}

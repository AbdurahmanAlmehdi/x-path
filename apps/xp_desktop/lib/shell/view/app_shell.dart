import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/add_project/view/add_project_page.dart';
import 'package:xp_desktop/approvals/bloc/pending_approvals_bloc.dart';
import 'package:xp_desktop/approvals/view/approval_review_sheet.dart';
import 'package:xp_desktop/approvals/view/approvals_page.dart';
import 'package:xp_desktop/credentials/view/credentials_page.dart';
import 'package:xp_desktop/engines/view/engines_page.dart';
import 'package:xp_desktop/job/view/job_page.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/onboarding/view/onboarding_page.dart';
import 'package:xp_desktop/project_overview/view/project_overview_page.dart';
import 'package:xp_desktop/projects/bloc/projects_bloc.dart';
import 'package:xp_desktop/projects/view/no_projects_page.dart';
import 'package:xp_desktop/releases/view/releases_page.dart';
import 'package:xp_desktop/runners/view/runners_page.dart';
import 'package:xp_desktop/shell/cubit/shell_cubit.dart';
import 'package:xp_desktop/shell/widgets/shell_page.dart';
import 'package:xp_desktop/shell/widgets/sidebar.dart';
import 'package:xp_desktop/storage/view/storage_page.dart';
import 'package:xp_desktop/tests/view/tests_page.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';
import 'package:xp_desktop/workflow_builder/view/workflow_builder_page.dart';

/// ⇧⌘A (Keyboard guide): reviews the approval of the shown project that
/// expires first, else opens the approvals inbox.
void reviewApprovals(BuildContext context) {
  final shell = context.read<ShellCubit>();
  final projectId =
      shell.projectId ??
      (shell.state is HomeDestination
          ? context.read<ProjectsBloc>().state.projects.firstOrNull?.id
          : null);
  final waiting = projectId == null
      ? const <Approval>[]
      : context.read<PendingApprovalsBloc>().state.of(projectId);
  if (waiting.isEmpty) {
    shell.show(const ApprovalsDestination());
    return;
  }
  unawaited(showApprovalReview(context, waiting.first.id));
}

/// The window: the sidebar and the content area of the destination.
class AppShell extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(
        LogicalKeyboardKey.keyA,
        meta: true,
        shift: true,
      ): () =>
          reviewApprovals(context),
    },
    child: Material(
      color: context.xpColors.surfaceWindow,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Sidebar(),
          const XpHairline(vertical: true),
          Expanded(
            child: BlocBuilder<ShellCubit, ShellDestination>(
              builder: (context, destination) => switch (destination) {
                HomeDestination() => const _Home(),
                ProjectDestination(:final projectId) => ProjectOverviewPage(
                  projectId,
                ),
                JobDestination(:final runId, :final jobId) => JobPage(
                  runId: runId,
                  jobId: jobId,
                ),
                ReleasesDestination(:final projectId, :final releaseId) =>
                  ReleasesPage(projectId: projectId, releaseId: releaseId),
                TestsDestination(:final projectId, :final jobId) => TestsPage(
                  projectId: projectId,
                  jobId: jobId,
                ),
                WorkflowsDestination(:final projectId, :final workflowId) =>
                  WorkflowBuilderPage(
                    projectId: projectId,
                    workflowId: workflowId,
                  ),
                RunnersDestination() => const RunnersPage(),
                StorageDestination() => const StoragePage(),
                ApprovalsDestination(:final approvalId) => ApprovalsPage(
                  approvalId: approvalId,
                ),
                AddProjectDestination() => const AddProjectPage(),
                CredentialsDestination(:final projectId) => CredentialsPage(
                  projectId: projectId,
                ),
                EnginesDestination() => const EnginesPage(),
                OnboardingDestination() => const OnboardingPage(),
              },
            ),
          ),
        ],
      ),
    ),
  );
}

class _Home extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ProjectsBloc>().state;
    if (!state.loaded) {
      return ShellPage(title: context.l10n.appTitle, child: const SizedBox());
    }
    if (state.projects.isEmpty) return const NoProjectsPage();
    return ProjectOverviewPage(state.projects.first.id);
  }
}

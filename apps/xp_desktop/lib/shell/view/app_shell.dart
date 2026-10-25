import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/add_project/view/add_project_page.dart';
import 'package:xp_desktop/app/app_services.dart';
import 'package:xp_desktop/approvals/bloc/pending_approvals_bloc.dart';
import 'package:xp_desktop/approvals/view/approval_review_sheet.dart';
import 'package:xp_desktop/approvals/view/approvals_page.dart';
import 'package:xp_desktop/credentials/view/credentials_page.dart';
import 'package:xp_desktop/dispatch/view/dispatch_sheet.dart';
import 'package:xp_desktop/engines/view/engines_page.dart';
import 'package:xp_desktop/job/view/job_page.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/onboarding/view/onboarding_page.dart';
import 'package:xp_desktop/project_overview/view/project_overview_page.dart';
import 'package:xp_desktop/projects/bloc/projects_bloc.dart';
import 'package:xp_desktop/projects/view/no_projects_page.dart';
import 'package:xp_desktop/releases/view/releases_page.dart';
import 'package:xp_desktop/runners/view/runners_page.dart';
import 'package:xp_desktop/runs/view/runs_page.dart';
import 'package:xp_desktop/settings/view/settings_page.dart';
import 'package:xp_desktop/shell/cubit/shell_cubit.dart';
import 'package:xp_desktop/shell/widgets/shell_page.dart';
import 'package:xp_desktop/shell/widgets/sidebar.dart';
import 'package:xp_desktop/storage/view/storage_page.dart';
import 'package:xp_desktop/tests/view/tests_page.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';
import 'package:xp_desktop/workflow_builder/view/workflow_builder_page.dart';

/// The project the shell shows: the destination's, or the first one on
/// the home page.
String? shownProjectId(BuildContext context) {
  final shell = context.read<ShellCubit>();
  return shell.projectId ??
      (shell.state is HomeDestination
          ? context.read<ProjectsBloc>().state.projects.firstOrNull?.id
          : null);
}

/// ⇧⌘A (Keyboard guide): reviews the approval of the shown project that
/// expires first, else opens the approvals inbox.
void reviewApprovals(BuildContext context) {
  final shell = context.read<ShellCubit>();
  final projectId = shownProjectId(context);
  final waiting = projectId == null
      ? const <Approval>[]
      : context.read<PendingApprovalsBloc>().state.of(projectId);
  if (waiting.isEmpty) {
    shell.show(const ApprovalsDestination());
    return;
  }
  unawaited(showApprovalReview(context, waiting.first.id));
}

/// ⌘N (Keyboard guide): dispatches for the shown project, from any page
/// of it.
Future<void> dispatchShown(BuildContext context) async {
  final id = shownProjectId(context);
  final project = id == null
      ? null
      : context.read<ProjectsBloc>().state.byId(id);
  if (project != null) await dispatchFor(context, project);
}

/// ⌘1–⌘9 (Keyboard guide): shows the project in that place of the sidebar.
void showProjectAt(BuildContext context, int index) {
  final projects = context.read<ProjectsBloc>().state.projects;
  if (index < projects.length) {
    context.read<ShellCubit>().show(ProjectDestination(projects[index].id));
  }
}

const _digits = <LogicalKeyboardKey>[
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
  LogicalKeyboardKey.digit7,
  LogicalKeyboardKey.digit8,
  LogicalKeyboardKey.digit9,
];

/// The window: the sidebar and the content area of the destination.
/// XPath ▸ Settings… (⌘,) shows the settings.
class AppShell extends StatefulWidget {
  const new({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  StreamSubscription<void>? _settings;

  @override
  void initState() {
    super.initState();
    final shell = context.read<ShellCubit>();
    _settings = context.read<AppServices>().appMenu.settingsRequests.listen(
      (_) => shell.show(const SettingsDestination()),
    );
  }

  @override
  void dispose() {
    unawaited(_settings?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(
        LogicalKeyboardKey.keyA,
        meta: true,
        shift: true,
      ): () =>
          reviewApprovals(context),
      const SingleActivator(LogicalKeyboardKey.keyN, meta: true): () =>
          unawaited(dispatchShown(context)),
      for (final (index, digit) in _digits.indexed)
        SingleActivator(digit, meta: true): () => showProjectAt(context, index),
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
                RunsDestination(:final projectId) => RunsPage(
                  projectId: projectId,
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
                SettingsDestination(:final github) => SettingsPage(
                  github: github,
                ),
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
      return ShellPage(
        title: context.l10n.appTitle,
        child: const Padding(padding: EdgeInsets.all(20), child: XpLoading()),
      );
    }
    if (state.projects.isEmpty) return const NoProjectsPage();
    return ProjectOverviewPage(state.projects.first.id);
  }
}

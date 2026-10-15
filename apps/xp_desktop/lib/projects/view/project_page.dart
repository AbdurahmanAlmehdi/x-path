import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/projects/bloc/projects_bloc.dart';
import 'package:xp_desktop/projects/widgets/scan_summary.dart';
import 'package:xp_desktop/shell/cubit/shell_cubit.dart';
import 'package:xp_desktop/shell/widgets/shell_page.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';

/// One project: its scan, until the project overview of Phase 16a replaces
/// this page.
class ProjectPage extends StatelessWidget {
  const new(this.projectId, {super.key});

  final String projectId;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = context.watch<ProjectsBloc>().state;
    final project = state.byId(projectId);
    if (project == null) {
      return ShellPage(
        title: l10n.appTitle,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: XpMessage(XpStatus.scanInfo, l10n.projectGone),
        ),
      );
    }
    return ShellPage(
      title: project.fullName,
      subtitle: l10n.projectSubtitle(
        project.defaultBaseBranch,
        l10n.projectApps(project.profile.apps.length),
      ),
      actions: [
        XpButton(
          label: l10n.scanAgain,
          icon: PhosphorIconsRegular.arrowClockwise,
          busy: state.scanning == project.id,
          tooltip: context.canCommand ? null : l10n.readOnlyHint,
          onPressed: context.canCommand
              ? () => context.read<ProjectsBloc>().add(
                  ProjectScanRequested(project.id),
                )
              : null,
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (state.error case final error?) ...[
            XpMessage(XpStatus.scanError, error),
            const SizedBox(height: 12),
          ],
          ScanSummary(project),
        ],
      ),
    );
  }
}

/// The content area when the engine has no project yet.
class NoProjectsPage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    return ShellPage(
      title: l10n.appTitle,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              PhosphorIconsRegular.package,
              size: context.xpSizes.iconXl,
              color: colors.textTertiary,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.projectEmptyTitle,
              style: context.xpType.headline.copyWith(
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.projectEmptyBody,
              style: context.xpType.body.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: 20),
            XpButton(
              label: l10n.sidebarAddProject,
              kind: XpButtonKind.primary,
              onPressed: () => context.read<ShellCubit>().show(
                const AddProjectDestination(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

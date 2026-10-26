import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/approvals/bloc/pending_approvals_bloc.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/project_overview/widgets/release_status.dart';
import 'package:xp_desktop/projects/bloc/projects_bloc.dart';
import 'package:xp_desktop/projects/view/no_projects_page.dart';
import 'package:xp_desktop/shell/bloc/home_bloc.dart';
import 'package:xp_desktop/shell/cubit/shell_cubit.dart';
import 'package:xp_desktop/shell/widgets/shell_page.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';
import 'package:xp_repositories/xp_repositories.dart';

/// Home (U6d): a card per project with what is live, in review and running
/// and what needs the owner; NoProjects on an engine without any.
class HomePage extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final projects = context.watch<ProjectsBloc>().state;
    if (!projects.loaded) {
      return ShellPage(
        title: context.l10n.homeTitle,
        child: const Padding(padding: EdgeInsets.all(20), child: XpLoading()),
      );
    }
    if (projects.projects.isEmpty) return const NoProjectsPage();
    return BlocProvider(
      create: (context) => HomeBloc(
        releases: context.read<ReleasesRepository>(),
        jobs: context.read<JobsRepository>(),
      )..add(const HomeSubscriptionRequested()),
      child: HomeView(projects: projects.projects),
    );
  }
}

class HomeView extends StatelessWidget {
  const new({required this.projects, super.key});

  final List<Project> projects;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = context.watch<HomeBloc>().state;
    return ShellPage(
      title: l10n.homeTitle,
      subtitle: l10n.homeSubtitle(projects.length),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (state.error case final error?) ...[
            XpErrorState(
              error,
              onRetry: () => context.read<HomeBloc>().add(
                const HomeSubscriptionRequested(),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final project in projects)
                _ProjectCard(project: project, state: state),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const new({required this.project, required this.state});

  final Project project;
  final HomeState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final type = context.xpType;
    final needsYou = context
        .watch<PendingApprovalsBloc>()
        .state
        .of(project.id)
        .length;
    final live = state.liveOf(project.id);
    final review = state.inReviewOf(project.id);
    final running = state.runningOf(project.id);
    Widget line(XpStatus status, String text) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: XpStatusLabel(status, text),
    );
    return SizedBox(
      width: 320,
      child: XpTappable(
        label: project.fullName,
        onTap: () =>
            context.read<ShellCubit>().show(ProjectDestination(project.id)),
        child: XpPanel(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                project.fullName.split('/').last,
                style: type.title.copyWith(color: colors.textPrimary),
              ),
              Text(
                project.fullName,
                overflow: TextOverflow.ellipsis,
                style: type.caption.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: 6),
              if (live != null)
                line(
                  releaseStatus(live.state),
                  l10n.homeLive(versionLabel(live.version, live.build)),
                )
              else if (state.loaded)
                line(XpStatus.scanInfo, l10n.homeNothingLive),
              if (review != null)
                line(
                  releaseStatus(review.state),
                  l10n.homeInReview(
                    versionLabel(review.version, review.build),
                    l10n.releaseState(review.state),
                  ),
                ),
              if (running > 0)
                line(XpStatus.jobRunning, l10n.jobRunningCount(running)),
              if (needsYou > 0)
                line(
                  XpStatus.jobWaitingApproval,
                  l10n.overviewNeedsYou(needsYou),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

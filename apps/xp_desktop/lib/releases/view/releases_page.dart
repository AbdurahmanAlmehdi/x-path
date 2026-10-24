import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/approvals/widgets/needs_you_bar.dart';
import 'package:xp_desktop/dispatch/view/dispatch_sheet.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/project_overview/widgets/release_status.dart';
import 'package:xp_desktop/projects/bloc/projects_bloc.dart';
import 'package:xp_desktop/releases/bloc/release_board_bloc.dart';
import 'package:xp_desktop/releases/widgets/release_hero.dart';
import 'package:xp_desktop/releases/widgets/release_panels.dart';
import 'package:xp_desktop/releases/widgets/release_timeline.dart';
import 'package:xp_desktop/releases/widgets/store_lane.dart';
import 'package:xp_desktop/shell/cubit/shell_cubit.dart';
import 'package:xp_desktop/shell/widgets/shell_page.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/toast/cubit/toast_cubit.dart';
import 'package:xp_desktop/widgets/widgets.dart';
import 'package:xp_repositories/xp_repositories.dart';

/// The releases of a project (concept 3A, `Release-A-Lanes.dc.html`),
/// showing [releaseId] if given, else the one in flight.
class ReleasesPage extends StatelessWidget {
  const new({required this.projectId, this.releaseId, super.key});

  final String projectId;
  final String? releaseId;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final project = context.watch<ProjectsBloc>().state.byId(projectId);
    if (project == null) {
      return ShellPage(
        title: l10n.releasesTitle,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: XpMessage(XpStatus.scanInfo, l10n.projectGone),
        ),
      );
    }
    return BlocProvider(
      key: ValueKey((projectId, releaseId)),
      create: (context) =>
          ReleaseBoardBloc(
            releases: context.read<ReleasesRepository>(),
            approvals: context.read<ApprovalsRepository>(),
            projects: context.read<ProjectsRepository>(),
          )..add(
            ReleaseBoardSubscriptionRequested(projectId, releaseId: releaseId),
          ),
      child: ReleasesView(project: project),
    );
  }
}

class ReleasesView extends StatelessWidget {
  const new({required this.project, super.key});

  final Project project;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = context.watch<ReleaseBoardBloc>().state;
    final bloc = context.read<ReleaseBoardBloc>();
    final release = state.release;
    final name = project.fullName.split('/').last;
    final runId = release?.builds.lastOrNull?.runId;
    final canCommand = context.canCommand;
    return MultiBlocListener(
      listeners: [
        BlocListener<ReleaseBoardBloc, ReleaseBoardState>(
          listenWhen: (previous, current) =>
              current.builtRun != null && current.builtRun != previous.builtRun,
          listener: (context, state) => context.read<ShellCubit>().show(
            JobDestination(state.builtRun!.id, projectId: project.id),
          ),
        ),
        for (final (command, toast) in [
          (ReleaseCommand.marking, l10n.releaseMarkedToast),
          (ReleaseCommand.merging, l10n.releaseMergedToast),
        ])
          BlocListener<ReleaseBoardBloc, ReleaseBoardState>(
            listenWhen: (previous, current) =>
                previous.command == command &&
                current.command == ReleaseCommand.none &&
                current.error == null,
            listener: (context, _) => context.read<ToastCubit>().show(toast),
          ),
      ],
      child: ShellPage(
        cached: state.cached,
        title: release == null
            ? l10n.releasesTitle
            : l10n.releaseTitle(versionLabel(release.version, release.build)),
        subtitle: release == null
            ? name
            : [name, release.flavor, ?release.tag].join(' · '),
        actions: [
          if (release != null && state.releases.length > 1)
            XpSelect<String>(
              value: release.id,
              values: [for (final release in state.releases) release.id],
              labelOf: (id) {
                final item = state.releases.firstWhere((r) => r.id == id);
                return [
                  versionLabel(item.version, item.build),
                  item.flavor,
                  l10n.releaseState(item.state),
                ].join(' · ');
              },
              onChanged: (id) => bloc.add(ReleaseBoardReleaseSelected(id)),
            ),
          if (release != null)
            XpButton(
              label: l10n.releaseRefresh,
              icon: PhosphorIconsRegular.arrowClockwise,
              busy: state.command == ReleaseCommand.refreshing,
              tooltip: canCommand ? l10n.releaseRefreshHint : l10n.readOnlyHint,
              onPressed: canCommand && state.command == ReleaseCommand.none
                  ? () => bloc.add(const ReleaseBoardRefreshRequested())
                  : null,
            ),
          if (runId != null)
            XpButton(
              label: l10n.overviewOpenJob,
              icon: PhosphorIconsRegular.terminalWindow,
              onPressed: () => context.read<ShellCubit>().show(
                JobDestination(runId, projectId: project.id),
              ),
            ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NeedsYouBar(projectId: project.id),
            if (release != null && release.state == ReleaseState.live)
              MinVersionBanner(release: release),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (state.error case final error? when release == null)
                    XpErrorState(
                      error,
                      onRetry: () => bloc.add(
                        ReleaseBoardSubscriptionRequested(
                          project.id,
                          releaseId: state.selectedId,
                        ),
                      ),
                    )
                  else if (state.error case final error?) ...[
                    XpMessage.error(error),
                    const SizedBox(height: 12),
                  ],
                  if (release != null)
                    _Board(release: release, state: state)
                  else if (!state.loaded)
                    const XpLoading()
                  else if (state.error == null)
                    _NoRelease(project: project),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Board extends StatelessWidget {
  const new({required this.release, required this.state});

  final Release release;
  final ReleaseBoardState state;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ReleaseHero(release: release),
      const SizedBox(height: 24),
      XpSectionLabel(context.l10n.lanesTitle),
      const SizedBox(height: 10),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (index, store) in ReleaseStore.values.indexed) ...[
            if (index > 0) const SizedBox(width: 16),
            Expanded(
              child: StoreLane(release: release, store: store),
            ),
          ],
        ],
      ),
      const SizedBox(height: 16),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: ReleaseTimeline(
              release: release,
              approvals: state.approvals,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(flex: 4, child: ReleaseNotesPanel(release: release)),
          const SizedBox(width: 16),
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MinVersionPanel(release: release),
                const SizedBox(height: 16),
                ReleasePrPanel(release: release),
              ],
            ),
          ),
        ],
      ),
    ],
  );
}

class _NoRelease extends StatelessWidget {
  const new({required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    return Padding(
      padding: const EdgeInsets.only(top: 80),
      child: Column(
        children: [
          Icon(
            PhosphorIconsRegular.package,
            size: context.xpSizes.iconXl,
            color: colors.textTertiary,
          ),
          const SizedBox(height: 12),
          Text(
            l10n.overviewNoRelease,
            style: context.xpType.title.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.releasesEmpty,
            style: context.xpType.body.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: 16),
          XpButton(
            label: l10n.releasesDispatchProd,
            icon: PhosphorIconsRegular.paperPlaneTilt,
            kind: XpButtonKind.primary,
            hint: '⌘N',
            tooltip: context.canCommand ? null : l10n.readOnlyHint,
            onPressed: context.canCommand
                ? () =>
                      dispatchFor(context, project, workflowId: 'prod-release')
                : null,
          ),
        ],
      ),
    );
  }
}

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/job/widgets/job_status.dart';
import 'package:xp_desktop/job/widgets/pipeline_graph.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/project_overview/bloc/project_overview_bloc.dart';
import 'package:xp_desktop/project_overview/widgets/release_status.dart';
import 'package:xp_desktop/shell/cubit/shell_cubit.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';

/// The top of the overview (1A): the release in flight as the hero, drawn
/// as a rail of its run's stages and then the stores; or, with nothing in
/// flight, what is live in each store.
class ReleaseRail extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ProjectOverviewBloc>().state;
    final release = state.heroRelease;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: release == null
          ? _Quiet(state.releases)
          : _InFlight(release: release, state: state),
    );
  }
}

class _InFlight extends StatelessWidget {
  const new({required this.release, required this.state});

  final Release release;
  final ProjectOverviewState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final type = context.xpType;
    final status = releaseStatus(release.state);
    final run = state.heroRun;
    final sha = release.headSha ?? run?.run.sha;
    final runId = release.builds.lastOrNull?.runId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            XpStatusIcon(status, size: context.xpSizes.iconLg),
            const SizedBox(width: 10),
            Text(
              l10n.releaseState(release.state),
              style: type.hero.copyWith(color: colors.onContainer(status.pair)),
            ),
            const SizedBox(width: 12),
            Text(
              versionLabel(release.version, release.build),
              style: type.heroCode.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Tooltip(
                message: formatAbsolute(release.createdAt),
                child: Text(
                  [
                    release.flavor,
                    ?sha == null ? null : shortSha(sha),
                    l10n.overviewStarted(
                      formatWhen(release.createdAt, XpClock.now(context)),
                    ),
                  ].join(' · '),
                  overflow: TextOverflow.ellipsis,
                  style: type.caption.copyWith(color: colors.textSecondary),
                ),
              ),
            ),
            XpButton(
              label: l10n.overviewOpenRelease,
              kind: XpButtonKind.tertiary,
              onPressed: () => context.read<ShellCubit>().show(
                ReleasesDestination(release.projectId, releaseId: release.id),
              ),
            ),
            if (runId != null) ...[
              const SizedBox(width: 8),
              XpButton(
                label: l10n.overviewOpenJob,
                icon: PhosphorIconsRegular.terminalWindow,
                onPressed: () => context.read<ShellCubit>().show(
                  JobDestination(runId, projectId: release.projectId),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        PipelineGraph(
          stages: run == null
              ? const []
              : pipelineStages(
                  runJobs: run,
                  l10n: l10n,
                  now: XpClock.now(context),
                  engineName: context.engineName,
                  stageName: state.heroStageName,
                  runnerName: (id) => state.runners[id],
                ),
          onNodeTap: runId == null
              ? null
              : (jobId) => context.read<ShellCubit>().show(
                  JobDestination(
                    runId,
                    jobId: jobId,
                    projectId: release.projectId,
                  ),
                ),
          trailing: release.stores.isEmpty
              ? null
              : PipelineStage(
                  label: l10n.overviewInStores(
                    versionLabel(release.version, release.build),
                  ),
                  nodes: [
                    for (final store in release.stores)
                      PipelineNode(
                        name: l10n.storeName(store.store),
                        status: storeStatus(store.store, store.state),
                        icon: _storeIcon(store.store),
                        badge: XpBadge(
                          storeStatus(store.store, store.state),
                          l10n.storeState(store.store, store.state),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

IconData _storeIcon(ReleaseStore store) => switch (store) {
  ReleaseStore.apple => PhosphorIconsRegular.appStoreLogo,
  ReleaseStore.play => PhosphorIconsRegular.googlePlayLogo,
};

/// The newest release of [releases] that is live in [store].
Release? liveIn(List<Release> releases, ReleaseStore store) {
  for (final release in releases) {
    if (storeOf(release, store)?.state == StoreState.live) return release;
  }
  return null;
}

class _Quiet extends StatelessWidget {
  const new(this.releases);

  final List<Release> releases;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final type = context.xpType;
    final live = {
      for (final store in ReleaseStore.values) store: ?liveIn(releases, store),
    };
    final hero = switch (live.length) {
      0 => l10n.overviewNoRelease,
      2 => l10n.overviewLiveBoth,
      _ => l10n.overviewLiveIn(l10n.storeName(live.keys.single)),
    };
    final status = live.isEmpty ? XpStatus.releaseDraft : XpStatus.releaseLive;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            XpStatusIcon(status, size: context.xpSizes.iconLg),
            const SizedBox(width: 10),
            Text(
              hero,
              style: type.hero.copyWith(color: colors.onContainer(status.pair)),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            for (final (index, MapEntry(key: store, value: release))
                in live.entries.indexed) ...[
              if (index > 0) ...[
                const SizedBox(width: 16),
                const SizedBox(height: 34, child: XpHairline(vertical: true)),
                const SizedBox(width: 16),
              ],
              PipelineNodeTile(
                PipelineNode(
                  name: l10n.storeName(store),
                  status: XpStatus.releaseLive,
                  icon: _storeIcon(store),
                  badge: XpBadge(
                    storeStatus(store, StoreState.live),
                    l10n.storeState(store, StoreState.live),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                release.version,
                style: type.codeLg.copyWith(color: colors.textPrimary),
              ),
            ],
            const Spacer(),
            Text(
              l10n.overviewNothingInFlight,
              style: type.caption.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      ],
    );
  }
}

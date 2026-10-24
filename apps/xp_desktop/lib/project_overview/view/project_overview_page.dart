import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/approvals/widgets/needs_you_bar.dart';
import 'package:xp_desktop/credentials/view/flavor_credentials_sheet.dart';
import 'package:xp_desktop/dispatch/view/dispatch_sheet.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/project_overview/bloc/project_overview_bloc.dart';
import 'package:xp_desktop/project_overview/widgets/docked_console.dart';
import 'package:xp_desktop/project_overview/widgets/flavor_ledger.dart';
import 'package:xp_desktop/project_overview/widgets/release_rail.dart';
import 'package:xp_desktop/projects/bloc/projects_bloc.dart';
import 'package:xp_desktop/projects/widgets/scan_summary.dart';
import 'package:xp_desktop/runs/view/runs_page.dart';
import 'package:xp_desktop/shell/widgets/shell_page.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';
import 'package:xp_repositories/xp_repositories.dart';

/// The project overview (1A, `Main.dc.html`): the release in flight as a
/// rail, the flavor ledger, and the docked console.
class ProjectOverviewPage extends StatelessWidget {
  const new(this.projectId, {super.key});

  final String projectId;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final project = context.watch<ProjectsBloc>().state.byId(projectId);
    if (project == null) {
      return ShellPage(
        title: l10n.appTitle,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: XpMessage(XpStatus.scanInfo, l10n.projectGone),
        ),
      );
    }
    return BlocProvider(
      key: ValueKey(projectId),
      create: (context) => ProjectOverviewBloc(
        releases: context.read<ReleasesRepository>(),
        projects: context.read<ProjectsRepository>(),
        jobs: context.read<JobsRepository>(),
        workflows: context.read<WorkflowsRepository>(),
        runners: context.read<RunnersRepository>(),
      )..add(ProjectOverviewSubscriptionRequested(projectId)),
      child: ProjectOverviewView(project: project),
    );
  }
}

class ProjectOverviewView extends StatefulWidget {
  const new({required this.project, super.key});

  final Project project;

  @override
  State<ProjectOverviewView> createState() => _ProjectOverviewViewState();
}

class _ProjectOverviewViewState extends State<ProjectOverviewView> {
  var _console = true;

  Future<void> _dispatch() => dispatchFor(context, widget.project);

  Future<void> _showScan() {
    final projects = context.read<ProjectsBloc>();
    return showDialog<void>(
      context: context,
      barrierColor: context.xpColors.scrimDefault,
      builder: (_) => BlocProvider.value(
        value: projects,
        child: ScanDialog(projectId: widget.project.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final project = widget.project;
    final state = context.watch<ProjectOverviewBloc>().state;
    final bloc = context.read<ProjectOverviewBloc>();
    final apps = project.profile.apps;
    final flavors = {
      for (final app in apps)
        for (final flavor in app.flavors) flavor.name,
    }.toList();
    final jobs = state.heroRun?.jobs ?? const <Job>[];
    final running = jobs.where((job) => job.state == JobState.running).length;
    final needsYou = jobs
        .where((job) => job.state == JobState.waitingForApproval)
        .length;
    final canCommand = context.canCommand;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true): _dispatch,
        const SingleActivator(
          LogicalKeyboardKey.keyC,
          meta: true,
          shift: true,
        ): () =>
            setState(() => _console = !_console),
      },
      child: Focus(
        autofocus: true,
        child: ShellPage(
          title: project.fullName.split('/').last,
          cached: state.cached,
          subtitle: l10n.projectSubtitle(
            project.defaultBaseBranch,
            l10n.projectApps(apps.length),
          ),
          actions: [
            if (flavors.length > 1)
              XpSegmented<String?>(
                value: state.filter,
                values: [null, ...flavors],
                labelOf: (flavor) => flavor ?? l10n.overviewAll,
                onChanged: (flavor) =>
                    bloc.add(ProjectOverviewFilterChanged(flavor)),
              ),
            const SizedBox(width: 8),
            if (running == 0 && needsYou == 0)
              Text(
                l10n.overviewQuiet,
                style: context.xpType.caption.copyWith(
                  color: context.xpColors.textSecondary,
                ),
              ),
            if (running > 0)
              XpStatusLabel(XpStatus.jobRunning, l10n.jobRunningCount(running)),
            if (needsYou > 0)
              XpStatusLabel(
                XpStatus.jobWaitingApproval,
                l10n.overviewNeedsYou(needsYou),
              ),
            XpButton(
              label: l10n.overviewDispatch,
              hint: '⌘N',
              kind: XpButtonKind.primary,
              tooltip: canCommand ? null : l10n.readOnlyHint,
              onPressed: canCommand ? _dispatch : null,
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              NeedsYouBar(projectId: project.id),
              const ReleaseRail(),
              const XpHairline(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    if (state.error case final error?) ...[
                      XpErrorState(
                        error,
                        onRetry: () => bloc.add(
                          ProjectOverviewSubscriptionRequested(project.id),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (apps.isEmpty)
                      XpMessage(XpStatus.scanWarning, l10n.scanNoApps),
                    for (final app in apps) ...[
                      FlavorLedger(
                        app: app,
                        baseBranch: project.defaultBaseBranch,
                        releases: state.releases,
                        credentials: state.credentials,
                        filter:
                            app.flavors.any(
                              (flavor) => flavor.name == state.filter,
                            )
                            ? state.filter
                            : null,
                        onScan: _showScan,
                        onCredentials: (flavor) => showFlavorCredentialsSheet(
                          context,
                          project: project,
                          target: (
                            app: app.path,
                            appName: app.name,
                            flavor: flavor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    RecentRuns(projectId: project.id),
                  ],
                ),
              ),
              DockedConsole(
                open: _console,
                onToggle: () => setState(() => _console = !_console),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The scan of a project, from the ledger's "Scan" button: what Phase 15's
/// project page showed, with "Scan again".
class ScanDialog extends StatelessWidget {
  const new({required this.projectId, super.key});

  final String projectId;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final state = context.watch<ProjectsBloc>().state;
    final project = state.byId(projectId);
    return Dialog(
      backgroundColor: colors.surfaceOverlay,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.xpRadii.lg),
        side: BorderSide(color: colors.borderStrong),
      ),
      child: SizedBox(
        width: 1000,
        height: 640,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: XpPageHeader(
                title: l10n.overviewScanTitle,
                subtitle: project?.fullName,
                actions: [
                  XpButton(
                    label: l10n.scanAgain,
                    icon: PhosphorIconsRegular.arrowClockwise,
                    busy: state.scanning == projectId,
                    onPressed: context.canCommand
                        ? () => context.read<ProjectsBloc>().add(
                            ProjectScanRequested(projectId),
                          )
                        : null,
                  ),
                  XpButton(
                    label: l10n.overviewClose,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const XpHairline(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (state.error case final error?) ...[
                    XpMessage.error(error),
                    const SizedBox(height: 12),
                  ],
                  if (project != null) ScanSummary(project),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

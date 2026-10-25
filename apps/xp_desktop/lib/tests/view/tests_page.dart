import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/dispatch/view/dispatch_sheet.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/projects/bloc/projects_bloc.dart';
import 'package:xp_desktop/shell/cubit/shell_cubit.dart';
import 'package:xp_desktop/shell/widgets/shell_page.dart';
import 'package:xp_desktop/tests/bloc/tests_bloc.dart';
import 'package:xp_desktop/tests/widgets/baselines_panel.dart';
import 'package:xp_desktop/tests/widgets/test_lists.dart';
import 'package:xp_desktop/tests/widgets/test_run_summary.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';
import 'package:xp_repositories/xp_repositories.dart';

/// The tests of a project (PRODUCT §6.7): the latest run against the
/// baseline, new failures first. Shows the run of [jobId] if given.
class TestsPage extends StatelessWidget {
  const new({required this.projectId, this.jobId, super.key});

  final String projectId;
  final String? jobId;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final project = context.watch<ProjectsBloc>().state.byId(projectId);
    if (project == null) {
      return ShellPage(
        title: l10n.testsTitle,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: XpMessage(XpStatus.scanInfo, l10n.projectGone),
        ),
      );
    }
    return BlocProvider(
      key: ValueKey((projectId, jobId)),
      create: (context) => TestsBloc(
        tests: context.read<TestsRepository>(),
        jobs: context.read<JobsRepository>(),
      )..add(TestsSubscriptionRequested(projectId, jobId: jobId)),
      child: TestsView(project: project),
    );
  }
}

/// What [run] is called in the run picker: branch, app, when, baseline.
String knownRunLabel(KnownTestRun run, AppLocalizations l10n) => [
  run.branch ?? run.jobId,
  if (run.appPath case final app? when app != '.') app,
  if (run.createdAt case final at?)
    formatDateTime(at)
  else if (run.branch != null)
    l10n.testsRunThisSession,
  if (run.baseline) l10n.testsBaselineTag,
].join(' · ');

class TestsView extends StatelessWidget {
  const new({required this.project, super.key});

  final Project project;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = context.watch<TestsBloc>().state;
    final bloc = context.read<TestsBloc>();
    final response = state.run;
    final run = response?.run;
    final runs = state.runs;
    final shown = state.shownJobId;
    final job = state.job;
    final name = project.fullName.split('/').last;
    return ShellPage(
      title: l10n.testsTitle,
      cached: state.runCached,
      subtitle: [
        name,
        if (run?.appPath case final app? when app != '.') app,
        ?run?.branch,
      ].join(' · '),
      actions: [
        if (shown != null && runs.length > 1)
          XpSelect<String>(
            value: shown,
            values: [for (final run in runs) run.jobId],
            labelOf: (jobId) => knownRunLabel(
              runs.firstWhere((run) => run.jobId == jobId),
              l10n,
            ),
            onChanged: (jobId) => bloc.add(TestsRunSelected(jobId)),
          ),
        if (job?.runId case final runId?)
          XpButton(
            label: l10n.overviewOpenJob,
            icon: PhosphorIconsRegular.terminalWindow,
            onPressed: () => context.read<ShellCubit>().show(
              JobDestination(runId, jobId: job!.id, projectId: project.id),
            ),
          ),
      ],
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (state.error case final error?) ...[
            XpErrorState(
              error,
              onRetry: () => bloc.add(
                TestsSubscriptionRequested(project.id, jobId: shown),
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (state.runError case final error? when shown != null) ...[
            XpErrorState(
              error,
              onRetry: () => bloc.add(TestsRunSelected(shown)),
            ),
            const SizedBox(height: 12),
          ],
          if (response != null) ...[
            TestRunSummary(
              response: response,
              duration: state.duration,
              baseline: state.comparedBaseline,
            ),
            const SizedBox(height: 24),
            TestLists(response: response),
          ] else if (state.error == null &&
              (!state.loaded || (shown != null && state.runError == null)))
            const XpLoading()
          else if (state.loaded && runs.isEmpty)
            _NoRuns(project: project),
          if (state.baselines.isNotEmpty) ...[
            const SizedBox(height: 24),
            BaselinesPanel(
              baselines: state.baselines,
              shownJobId: shown,
              onShow: (jobId) => bloc.add(TestsRunSelected(jobId)),
            ),
          ],
        ],
      ),
    );
  }
}

class _NoRuns extends StatelessWidget {
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
            PhosphorIconsRegular.testTube,
            size: context.xpSizes.iconXl,
            color: colors.textTertiary,
          ),
          const SizedBox(height: 12),
          Text(
            l10n.testsEmptyTitle,
            style: context.xpType.title.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Text(
              l10n.testsEmptyBody,
              textAlign: TextAlign.center,
              style: context.xpType.body.copyWith(color: colors.textSecondary),
            ),
          ),
          const SizedBox(height: 16),
          XpButton(
            label: l10n.testsRun,
            icon: PhosphorIconsRegular.testTube,
            kind: XpButtonKind.primary,
            hint: '⌘N',
            tooltip: context.canCommand ? null : l10n.readOnlyHint,
            onPressed: context.canCommand
                ? () => dispatchFor(context, project, workflowId: 'test')
                : null,
          ),
        ],
      ),
    );
  }
}

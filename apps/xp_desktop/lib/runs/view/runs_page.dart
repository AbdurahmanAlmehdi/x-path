import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/job/widgets/job_status.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/projects/bloc/projects_bloc.dart';
import 'package:xp_desktop/runs/bloc/runs_bloc.dart';
import 'package:xp_desktop/runs/widgets/run_row.dart';
import 'package:xp_desktop/shell/cubit/shell_cubit.dart';
import 'package:xp_desktop/shell/widgets/shell_page.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';
import 'package:xp_repositories/xp_repositories.dart';

/// The runs of a project, newest first, wherever they were dispatched
/// from, filtered by state and workflow.
class RunsPage extends StatelessWidget {
  const new({required this.projectId, super.key});

  final String projectId;

  @override
  Widget build(BuildContext context) => BlocProvider(
    key: ValueKey(projectId),
    create: (context) => RunsBloc(
      jobs: context.read<JobsRepository>(),
      workflows: context.read<WorkflowsRepository>(),
      projectId: projectId,
      limit: 100,
    )..add(const RunsSubscriptionRequested()),
    child: RunsView(projectId: projectId),
  );
}

class RunsView extends StatelessWidget {
  const new({required this.projectId, super.key});

  final String projectId;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = context.watch<RunsBloc>().state;
    final bloc = context.read<RunsBloc>();
    final project = context.watch<ProjectsBloc>().state.byId(projectId);
    return ShellPage(
      title: l10n.runsTitle,
      subtitle: project?.fullName,
      actions: [
        XpSelect<String?>(
          value: state.workflowId,
          values: [null, for (final workflow in state.workflows) workflow.id],
          labelOf: (id) =>
              id == null ? l10n.runsAllWorkflows : state.workflowName(id) ?? id,
          onChanged: (id) =>
              bloc.add(RunsFilterChanged(state: state.state, workflowId: id)),
        ),
        XpSelect<RunState?>(
          value: state.state,
          values: const [null, ...RunState.values],
          labelOf: (value) =>
              value == null ? l10n.runsAllStates : l10n.runState(value),
          onChanged: (value) => bloc.add(
            RunsFilterChanged(state: value, workflowId: state.workflowId),
          ),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          XpPanel(
            child: RunList(state: state, empty: l10n.runsNone),
          ),
        ],
      ),
    );
  }
}

/// [state]'s runs, a row each; [empty] when there is none.
class RunList extends StatelessWidget {
  const new({required this.state, required this.empty, super.key});

  final RunsState state;
  final String empty;

  @override
  Widget build(BuildContext context) {
    if (state.error case final error? when state.runs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: XpMessage(XpStatus.scanError, error),
      );
    }
    if (!state.loaded) return const SizedBox(height: 40);
    if (state.runs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          empty,
          style: context.xpType.body.copyWith(
            color: context.xpColors.textSecondary,
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, run) in state.runs.indexed) ...[
          if (index > 0) const XpHairline(),
          RunRow(
            key: ValueKey(run.id),
            run: run,
            workflowName: state.workflowName(run.workflowId),
          ),
        ],
      ],
    );
  }
}

/// The Overview's "Recent runs": the last runs of any workflow, and a way
/// to all of them.
class RecentRuns extends StatelessWidget {
  const new({required this.projectId, super.key});

  final String projectId;

  @override
  Widget build(BuildContext context) => BlocProvider(
    key: ValueKey(('recent-runs', projectId)),
    create: (context) => RunsBloc(
      jobs: context.read<JobsRepository>(),
      workflows: context.read<WorkflowsRepository>(),
      projectId: projectId,
      limit: 5,
    )..add(const RunsSubscriptionRequested()),
    child: Builder(
      builder: (context) {
        final l10n = context.l10n;
        final state = context.watch<RunsBloc>().state;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                XpSectionLabel(l10n.runsRecent),
                const Spacer(),
                XpButton(
                  label: l10n.runsAll,
                  kind: XpButtonKind.tertiary,
                  size: XpButtonSize.small,
                  onPressed: () => context.read<ShellCubit>().show(
                    RunsDestination(projectId),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            XpPanel(
              child: RunList(state: state, empty: l10n.runsNoneYet),
            ),
          ],
        );
      },
    ),
  );
}

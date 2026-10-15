import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/job/widgets/pipeline_graph.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';
import 'package:xp_desktop/workflow_builder/bloc/workflow_edits.dart';
import 'package:xp_repositories/xp_repositories.dart';

/// The visual editor's pipeline, drawn like the job view's graph (2A):
/// stages left to right, a node per job. A click selects the workflow, a
/// stage or a job for the inspector; "Add job" and "Add stage" grow it.
class WorkflowGraph extends StatelessWidget {
  const new({
    required this.document,
    required this.selection,
    required this.onSelect,
    required this.onEdit,
    this.enabled = true,
    super.key,
  });

  final WorkflowDocument document;
  final WorkflowSelection selection;
  final ValueChanged<WorkflowSelection> onSelect;

  /// Called with the edited document and what to select after the edit.
  final void Function(WorkflowDocument document, WorkflowSelection selection)
  onEdit;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final stages = document.stages;
    return XpPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              XpSectionLabel(l10n.workflowsPipeline),
              const Spacer(),
              _Caption(
                label: document.name ?? l10n.workflowsWorkflow,
                selected: selection.stage == null,
                onTap: () => onSelect(WorkflowSelection.workflow),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (index, stage) in stages.indexed) ...[
                  if (index > 0) const _Wire(),
                  _StageColumn(
                    index: index,
                    stage: stage,
                    selection: selection,
                    enabled: enabled,
                    onSelect: onSelect,
                    onAddJob: () => onEdit(
                      document.addJob(index),
                      WorkflowSelection(stage: index, job: stage.jobs.length),
                    ),
                  ),
                ],
                if (stages.isNotEmpty) const SizedBox(width: 16),
                XpButton(
                  label: l10n.workflowsAddStage,
                  icon: PhosphorIconsRegular.plus,
                  kind: XpButtonKind.tertiary,
                  size: XpButtonSize.small,
                  onPressed: enabled
                      ? () => onEdit(
                          document.addStage(
                            l10n.workflowsNewStage(stages.length + 1),
                          ),
                          WorkflowSelection(stage: stages.length, job: 0),
                        )
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StageColumn extends StatelessWidget {
  const new({
    required this.index,
    required this.stage,
    required this.selection,
    required this.enabled,
    required this.onSelect,
    required this.onAddJob,
  });

  final int index;
  final WorkflowStage stage;
  final WorkflowSelection selection;
  final bool enabled;
  final ValueChanged<WorkflowSelection> onSelect;
  final VoidCallback onAddJob;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Caption(
          label: stage.name.isEmpty
              ? l10n.workflowsStage(index + 1)
              : stage.name,
          selected: selection.stage == index && selection.job == null,
          onTap: () => onSelect(WorkflowSelection(stage: index)),
        ),
        const SizedBox(height: 8),
        for (final (j, job) in stage.jobs.indexed) ...[
          if (j > 0) const SizedBox(height: 6),
          PipelineNodeTile(
            PipelineNode(
              name: job.id,
              status: XpStatus.jobSkipped,
              icon: job.steps.any((step) => step.gate != null)
                  ? PhosphorIconsRegular.handPalm
                  : PhosphorIconsRegular.terminalWindow,
              runner: [
                l10n.workflowsSteps(job.steps.length),
                for (final axis in job.matrix) '× ${axis.name}',
              ].join(' · '),
              selected: selection.stage == index && selection.job == j,
            ),
            onTap: () => onSelect(WorkflowSelection(stage: index, job: j)),
          ),
        ],
        const SizedBox(height: 6),
        XpButton(
          label: l10n.workflowsAddJob,
          icon: PhosphorIconsRegular.plus,
          kind: XpButtonKind.tertiary,
          size: XpButtonSize.small,
          onPressed: enabled ? onAddJob : null,
        ),
      ],
    );
  }
}

/// A stage's caption (or the workflow's), in mono caps, that selects it.
class _Caption extends StatelessWidget {
  const new({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.xpColors;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(context.xpRadii.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: selected ? colors.surfaceSelected : null,
            borderRadius: BorderRadius.circular(context.xpRadii.sm),
            border: Border.all(
              color: selected ? colors.borderStrong : Colors.transparent,
            ),
          ),
          child: XpSectionLabel(
            label,
            color: selected ? colors.textPrimary : null,
          ),
        ),
      ),
    );
  }
}

/// The wire between two stages: they run one after the other.
class _Wire extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(
      top: 28 + context.xpSizes.nodeHeight / 2,
      left: 6,
      right: 6,
    ),
    child: Container(
      width: 28,
      height: context.xpBorders.widthEmphasis,
      color: context.xpColors.borderStrong,
    ),
  );
}

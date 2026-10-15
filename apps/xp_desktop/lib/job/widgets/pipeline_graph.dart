import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/job/widgets/job_status.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';
import 'package:xp_repositories/xp_repositories.dart';

/// One node of a [PipelineGraph]: a job, or a store on the overview.
class PipelineNode {
  const new({
    required this.name,
    required this.status,
    this.id,
    this.runner,
    this.duration,
    this.badge,
    this.icon,
    this.selected = false,
  });

  /// The job's id, when the node is a job.
  final String? id;
  final String name;
  final XpStatus status;

  /// Where it runs.
  final String? runner;

  /// How long it ran, `type.code`.
  final String? duration;

  /// A badge after the name instead of the status icon (a store's status).
  final Widget? badge;

  /// A platform mark before the name instead of the status icon.
  final IconData? icon;
  final bool selected;
}

/// One column of a [PipelineGraph].
class PipelineStage {
  const new({
    required this.label,
    required this.nodes,
    this.done = false,
    this.needsYou = false,
  });

  /// The stage's caption, mono caps.
  final String label;
  final List<PipelineNode> nodes;

  /// Whether every job of the stage is done: the wire after it is solid.
  final bool done;

  /// Whether a job of the stage waits for an approval: the caption takes
  /// the attention colour.
  final bool needsYou;
}

/// The stages of [runJobs] as the graph draws them: a column per stage, a
/// node per job, named by the workflow's stage names where [stageName] knows
/// them.
List<PipelineStage> pipelineStages({
  required RunJobs runJobs,
  required AppLocalizations l10n,
  required DateTime now,
  required String engineName,
  String? Function(int stage)? stageName,
  String? Function(String runnerId)? runnerName,
  String? selectedJobId,
}) {
  final byStage = <int, List<RunJob>>{};
  for (final job in runJobs.run.jobs) {
    (byStage[job.stage] ??= []).add(job);
  }
  final stages = byStage.keys.toList()..sort();
  return [
    for (final stage in stages)
      PipelineStage(
        label: stageName?.call(stage) ?? l10n.jobStage(stage + 1),
        done: byStage[stage]!.every((job) => job.state == JobState.succeeded),
        needsYou: byStage[stage]!.any(
          (job) => job.state == JobState.waitingForApproval,
        ),
        nodes: [
          for (final summary in byStage[stage]!)
            _node(
              summary,
              runJobs.job(summary.id),
              now: now,
              engineName: engineName,
              runnerName: runnerName,
              selected: summary.id == selectedJobId,
            ),
        ],
      ),
  ];
}

PipelineNode _node(
  RunJob summary,
  Job? job, {
  required DateTime now,
  required String engineName,
  required String? Function(String runnerId)? runnerName,
  required bool selected,
}) {
  final state = job?.state ?? summary.state;
  final ran = elapsed(job?.startedAt, job?.finishedAt, now);
  final runnerId = job?.runnerId;
  final started = job?.startedAt != null;
  return PipelineNode(
    id: summary.id,
    name: summary.name,
    status: jobStatus(state),
    runner: !started
        ? null
        : runnerId == null
        ? engineName
        : runnerName?.call(runnerId) ?? runnerId,
    duration: ran == null ? null : formatDuration(ran),
    selected: selected,
  );
}

/// The pipeline graph of 2A and of the overview's release rail: stages left
/// to right, joined by wires that are solid once the stage before finished
/// and dashed while it has not.
class PipelineGraph extends StatelessWidget {
  const new({required this.stages, this.onNodeTap, this.trailing, super.key});

  final List<PipelineStage> stages;

  /// Called with a job node's id when it is clicked.
  final ValueChanged<String>? onNodeTap;

  /// After the stages, past a vertical rule (the overview's store column).
  final PipelineStage? trailing;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (index, stage) in stages.indexed) ...[
            if (index > 0) _Wire(solid: stages[index - 1].done),
            _Stage(stage, onNodeTap: onNodeTap),
          ],
          if (trailing case final trailing?) ...[
            const SizedBox(width: 20),
            const XpHairline(vertical: true),
            const SizedBox(width: 20),
            _Stage(trailing),
          ],
        ],
      ),
    ),
  );
}

class _Stage extends StatelessWidget {
  const new(this.stage, {this.onNodeTap});

  final PipelineStage stage;
  final ValueChanged<String>? onNodeTap;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      XpSectionLabel(
        stage.needsYou
            ? '${stage.label} · ${context.l10n.jobNeedsYou}'
            : stage.label,
        color: stage.needsYou
            ? context.xpColors.statusAttentionOnContainer
            : null,
      ),
      const SizedBox(height: 8),
      for (final (index, node) in stage.nodes.indexed) ...[
        if (index > 0) const SizedBox(height: 6),
        PipelineNodeTile(
          node,
          onTap: node.id == null || onNodeTap == null
              ? null
              : () => onNodeTap!(node.id!),
        ),
      ],
    ],
  );
}

/// One node: status icon, name, runner and duration in a 34px box.
class PipelineNodeTile extends StatefulWidget {
  const new(this.node, {this.onTap, super.key});

  final PipelineNode node;
  final VoidCallback? onTap;

  @override
  State<PipelineNodeTile> createState() => _PipelineNodeTileState();
}

class _PipelineNodeTileState extends State<PipelineNodeTile> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.xpColors;
    final type = context.xpType;
    final node = widget.node;
    final status = node.status;
    final quiet =
        status == XpStatus.jobQueued || status == XpStatus.jobCancelled;
    final (border, width) = switch (status) {
      XpStatus.jobRunning => (colors.infoDefault, 2.0),
      XpStatus.jobFailed => (colors.negativeDefault, 1.0),
      XpStatus.jobWaitingApproval => (colors.statusAttentionOnContainer, 1.0),
      _ when node.selected => (colors.borderStrong, 1.0),
      _ => (colors.borderDefault, 1.0),
    };
    final tile = AnimatedContainer(
      duration: context.xpMotion.durationFast,
      height: context.xpSizes.nodeHeight,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: node.selected
            ? colors.surfaceSelected
            : _hovered
            ? colors.surfaceHover
            : colors.surfaceRaised,
        borderRadius: BorderRadius.circular(context.xpRadii.md),
        border: Border.all(color: border, width: width),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (node.icon case final icon?)
            Icon(icon, size: context.xpSizes.iconSm, color: colors.textPrimary)
          else
            XpStatusIcon(status),
          const SizedBox(width: 6),
          Text(
            node.name,
            style: type.bodyStrong.copyWith(
              color: quiet ? colors.textSecondary : colors.textPrimary,
            ),
          ),
          if (node.runner case final runner?) ...[
            const SizedBox(width: 8),
            Text(
              runner,
              style: type.caption.copyWith(color: colors.textSecondary),
            ),
          ],
          if (node.duration case final duration?) ...[
            const SizedBox(width: 8),
            Text(
              duration,
              style: type.code.copyWith(color: colors.textSecondary),
            ),
          ],
          if (node.badge case final badge?) ...[
            const SizedBox(width: 8),
            badge,
          ],
        ],
      ),
    );
    if (widget.onTap == null) return tile;
    return Semantics(
      button: true,
      selected: node.selected,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(onTap: widget.onTap, child: tile),
      ),
    );
  }
}

class _Wire extends StatelessWidget {
  const new({required this.solid});

  final bool solid;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 22, left: 6, right: 6),
    child: SizedBox(
      width: 28,
      height: context.xpSizes.nodeHeight,
      child: CustomPaint(
        painter: _WirePainter(
          color: solid
              ? context.xpColors.borderStrong
              : context.xpColors.borderDefault,
          width: context.xpBorders.widthEmphasis,
          dashed: !solid,
        ),
      ),
    ),
  );
}

class _WirePainter extends CustomPainter {
  const new({required this.color, required this.width, required this.dashed});

  final Color color;
  final double width;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width;
    final y = size.height / 2;
    if (!dashed) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      return;
    }
    for (var x = 0.0; x < size.width; x += 6) {
      canvas.drawLine(Offset(x, y), Offset(x + 3, y), paint);
    }
  }

  @override
  bool shouldRepaint(_WirePainter oldDelegate) =>
      color != oldDelegate.color ||
      width != oldDelegate.width ||
      dashed != oldDelegate.dashed;
}

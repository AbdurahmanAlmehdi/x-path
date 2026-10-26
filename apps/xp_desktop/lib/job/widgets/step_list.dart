import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart' hide StepState;
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/app/app_services.dart';
import 'package:xp_desktop/job/bloc/job_view_bloc.dart';
import 'package:xp_desktop/job/widgets/job_status.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/toast/cubit/toast_cubit.dart';
import 'package:xp_desktop/widgets/widgets.dart';

/// The column beside the log: the steps of [job] (one can be picked to
/// resume from), then its resume plan when it stopped short, else its
/// artifacts.
class StepAside extends StatelessWidget {
  const new({required this.job, super.key});

  final Job job;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = context.watch<JobViewBloc>().state;
    final runner = job.runnerId == null
        ? context.engineName
        : state.runners[job.runnerId] ?? job.runnerId!;
    final now = XpClock.now(context);
    final resumable = isResumable(job.state);
    final from = resumable ? resumeFrom(job, state.selectedStep) : null;
    return ColoredBox(
      color: context.xpColors.surfaceRaised,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: XpSectionLabel(l10n.jobStepsOf(job.name ?? job.id, runner)),
          ),
          for (final step in job.steps)
            _StepRow(
              step: step,
              now: now,
              selected: state.selectedStep == step.ordinal,
              onTap: resumable
                  ? () => context.read<JobViewBloc>().add(
                      JobViewStepSelected(
                        state.selectedStep == step.ordinal
                            ? null
                            : step.ordinal,
                      ),
                    )
                  : null,
            ),
          const SizedBox(height: 16),
          if (from != null)
            _ResumePlan(job: job, from: from, runner: runner)
          else if (state.artifacts.isNotEmpty)
            _Artifacts(state.artifacts, downloads: state.downloads),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const new({
    required this.step,
    required this.now,
    required this.selected,
    required this.onTap,
  });

  final JobStep step;
  final DateTime now;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.xpColors;
    final type = context.xpType;
    final ran = elapsed(step.startedAt, step.finishedAt, now);
    final waiting = step.state == StepState.pending;
    final row = Container(
      height: context.xpSizes.rowDefault,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: selected ? colors.selectionDefault : null,
        borderRadius: BorderRadius.circular(context.xpRadii.md),
      ),
      child: Row(
        children: [
          XpStatusIcon(stepStatus(step.state)),
          const SizedBox(width: 6),
          Expanded(
            child: Tooltip(
              message: step.message ?? '',
              child: Text(
                context.l10n.stepKind(step.kind),
                overflow: TextOverflow.ellipsis,
                style: type.body.copyWith(
                  color: waiting ? colors.textSecondary : colors.textPrimary,
                ),
              ),
            ),
          ),
          if (ran != null)
            Text(
              formatDuration(ran),
              style: type.code.copyWith(color: colors.textSecondary),
            ),
        ],
      ),
    );
    if (onTap == null) return row;
    return XpTappable(onTap: onTap, selected: selected, child: row);
  }
}

class _ResumePlan extends StatelessWidget {
  const new({required this.job, required this.from, required this.runner});

  final Job job;
  final int from;
  final String runner;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _Section(
      label: l10n.jobResumePlan,
      rows: [
        if (from > 0)
          _PlanRow(
            status: XpStatus.jobSkipped,
            text: l10n.jobResumeKept(from),
            meta: l10n.jobAlreadyDone,
          ),
        _PlanRow(
          status: XpStatus.jobQueued,
          text: l10n.jobResumeRuns(l10n.stepKind(job.steps[from].kind)),
          meta: runner,
        ),
      ],
    );
  }
}

/// The artifacts of the job: Download saves one where the owner picks;
/// then Reveal shows it in Finder and Copy path copies where it is.
class _Artifacts extends StatelessWidget {
  const new(this.artifacts, {required this.downloads});

  final List<Artifact> artifacts;

  /// Where each artifact was downloaded to, by id.
  final Map<String, String> downloads;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final bloc = context.read<JobViewBloc>();
    final busy = bloc.state.command == JobViewCommand.downloading;
    return _Section(
      label: l10n.jobArtifactsLabel,
      rows: [
        for (final artifact in artifacts)
          GestureDetector(
            key: ValueKey(('artifact', artifact.id)),
            // A right click reveals a downloaded artifact (U6c).
            onSecondaryTapUp: (details) =>
                showXpContextMenu(context, details.globalPosition, [
                  if (downloads[artifact.id] case final path?) ...[
                    XpMenuAction(
                      l10n.menuRevealArtifact,
                      () => context.read<AppServices>().revealFile(path),
                    ),
                    XpMenuAction.copy(l10n.jobArtifactCopyPath, path),
                  ] else
                    XpMenuAction(
                      l10n.jobArtifactDownload,
                      () =>
                          bloc.add(JobViewArtifactDownloadRequested(artifact)),
                    ),
                ]),
            child: Row(
              children: [
                Expanded(
                  child: _PlanRow(
                    icon: PhosphorIconsRegular.package,
                    text: artifact.name,
                    meta: formatSize(artifact.size),
                  ),
                ),
                _ArtifactAction(
                  icon: PhosphorIconsRegular.downloadSimple,
                  tooltip: l10n.jobArtifactDownload,
                  onTap: busy
                      ? null
                      : () => bloc.add(
                          JobViewArtifactDownloadRequested(artifact),
                        ),
                ),
                if (downloads[artifact.id] case final path?) ...[
                  _ArtifactAction(
                    icon: PhosphorIconsRegular.folderOpen,
                    tooltip: l10n.jobArtifactReveal,
                    onTap: () => context.read<AppServices>().revealFile(path),
                  ),
                  _ArtifactAction(
                    icon: PhosphorIconsRegular.copy,
                    tooltip: l10n.jobArtifactCopyPath,
                    onTap: () async {
                      await Clipboard.setData(ClipboardData(text: path));
                      if (context.mounted) {
                        context.read<ToastCubit>().show(l10n.jobArtifactCopied);
                      }
                    },
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _ArtifactAction extends StatelessWidget {
  const new({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Semantics(
      button: true,
      label: tooltip,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(context.xpRadii.md),
        child: SizedBox.square(
          dimension: context.xpSizes.controlSm,
          child: Icon(
            icon,
            size: context.xpSizes.iconSm,
            color: onTap == null
                ? context.xpColors.textDisabled
                : context.xpColors.textSecondary,
          ),
        ),
      ),
    ),
  );
}

class _Section extends StatelessWidget {
  const new({required this.label, required this.rows});

  final String label;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [XpSectionLabel(label), const SizedBox(height: 6), ...rows],
    ),
  );
}

class _PlanRow extends StatelessWidget {
  const new({required this.text, required this.meta, this.status, this.icon});

  final XpStatus? status;
  final IconData? icon;
  final String text;
  final String meta;

  @override
  Widget build(BuildContext context) {
    final colors = context.xpColors;
    final type = context.xpType;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          if (status case final status?)
            XpStatusIcon(status)
          else
            Icon(
              icon,
              size: context.xpSizes.iconSm,
              color: colors.textSecondary,
            ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: type.body.copyWith(color: colors.textPrimary),
            ),
          ),
          const SizedBox(width: 6),
          Text(meta, style: type.caption.copyWith(color: colors.textSecondary)),
        ],
      ),
    );
  }
}

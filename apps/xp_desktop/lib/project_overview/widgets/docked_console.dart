import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/job/view/job_page.dart';
import 'package:xp_desktop/job/widgets/job_status.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/project_overview/bloc/project_overview_bloc.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';

/// The console docked at the bottom of the overview, like Xcode's debug
/// area: the live log of the job of the release in flight that runs, or a
/// 34px strip that says what ran last. ⇧⌘C shows and hides it.
class DockedConsole extends StatelessWidget {
  const new({required this.open, required this.onToggle, super.key});

  /// Whether the console is shown at its full height.
  final bool open;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ProjectOverviewBloc>().state;
    final jobs = state.heroRun?.jobs ?? const <Job>[];
    final running = jobs
        .where((job) => job.state == JobState.running)
        .firstOrNull;
    if (running == null || !open) {
      final last =
          running ??
          jobs
              .where((job) => job.finishedAt != null)
              .fold<Job?>(
                null,
                (last, job) =>
                    last == null || job.finishedAt!.isAfter(last.finishedAt!)
                    ? job
                    : last,
              );
      return _Strip(last: last, onToggle: running == null ? null : onToggle);
    }
    return SizedBox(
      height: context.xpSizes.consoleHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const XpHairline(),
          Expanded(
            child: JobLogPane(
              job: running,
              runnerName: state.runners[running.runnerId],
            ),
          ),
        ],
      ),
    );
  }
}

class _Strip extends StatelessWidget {
  const new({required this.last, required this.onToggle});

  final Job? last;

  /// `null` while there is nothing to show.
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final type = context.xpType;
    final job = last;
    final strip = Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: colors.surfaceSidebar,
        border: Border(top: BorderSide(color: colors.borderDefault)),
      ),
      child: Row(
        children: [
          Icon(
            PhosphorIconsRegular.terminalWindow,
            size: context.xpSizes.iconMd,
            color: colors.textSecondary,
          ),
          const SizedBox(width: 6),
          Text(
            l10n.consoleTitle,
            style: type.bodyStrong.copyWith(color: colors.textPrimary),
          ),
          if (job != null) ...[
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                l10n.consoleLast(job.name ?? job.id),
                overflow: TextOverflow.ellipsis,
                style: type.body.copyWith(color: colors.textSecondary),
              ),
            ),
            const SizedBox(width: 8),
            XpStatusLabel(jobStatus(job.state), l10n.jobState(job.state)),
          ],
          const Spacer(),
          Text('⇧⌘C', style: type.code.copyWith(color: colors.textTertiary)),
        ],
      ),
    );
    if (onToggle == null) return strip;
    return XpTappable(onTap: onToggle, radius: 0, child: strip);
  }
}

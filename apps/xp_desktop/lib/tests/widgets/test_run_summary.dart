import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';

/// The hero of a test run (its new failures against the baseline), what it
/// was compared with, and its counts (`Main.dc.html`, the Tests panel).
class TestRunSummary extends StatelessWidget {
  const new({required this.response, this.duration, this.baseline, super.key});

  final TestRunResponse response;

  /// How long the job's `test` step ran, if known.
  final Duration? duration;

  /// The baseline the run was compared with, if the project still has it.
  final TestBaseline? baseline;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final type = context.xpType;
    final run = response.run;
    final diff = run.diff;
    final newFailures = diff.newFailures.length;
    final status = newFailures == 0
        ? XpStatus.jobSucceeded
        : XpStatus.jobFailed;
    final meta = type.caption.copyWith(color: colors.textSecondary);
    final code = type.code.copyWith(color: colors.textSecondary);
    final comparison = run.baseline
        ? l10n.testsIsBaseline(run.branch)
        : diff.comparedTo == null
        ? l10n.testsNoBaseline
        : baseline == null
        ? l10n.testsComparedToJob(diff.comparedTo!)
        : l10n.testsComparedTo(
            baseline!.branch,
            formatDateTime(baseline!.createdAt),
          );
    final counts = run.counts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            XpStatusIcon(status, size: context.xpSizes.iconLg),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                newFailures == 0
                    ? l10n.testsNoNewFailures
                    : l10n.testsNewFailures(newFailures),
                style: type.hero.copyWith(
                  color: colors.onContainer(status.pair),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(run.branch, style: code),
            Text('·', style: meta),
            Text(formatDateTime(run.createdAt), style: meta),
            if (duration case final duration?) ...[
              Text('·', style: meta),
              Text(formatDuration(duration), style: code),
            ],
            Text('·', style: meta),
            Text(comparison, style: meta),
          ],
        ),
        const SizedBox(height: 16),
        XpPanel(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Wrap(
            spacing: 28,
            runSpacing: 12,
            children: [
              _Stat(newFailures, l10n.testsStatNew),
              _Stat(diff.stillFailing, l10n.testsStatInBaseline),
              _Stat(diff.fixed.length, l10n.testsStatFixed),
              _Stat(counts.passed, l10n.testsStatPassed),
              _Stat(counts.failed, l10n.testsStatFailed),
              _Stat(counts.errored, l10n.testsStatErrored),
              _Stat(counts.skipped, l10n.testsStatSkipped),
              if (diff.missing.isNotEmpty)
                _Stat(diff.missing.length, l10n.testsStatMissing),
            ],
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const new(this.value, this.label);

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        formatCount(value),
        style: context.xpType.codeLg.copyWith(
          color: context.xpColors.textPrimary,
        ),
      ),
      Text(
        label,
        style: context.xpType.caption.copyWith(
          color: context.xpColors.textSecondary,
        ),
      ),
    ],
  );
}

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';
import 'package:xp_repositories/xp_repositories.dart';

/// Asks before cancelling a run (`Job-A-Cancel`): what stops now, what is
/// kept, what never starts. `true` when the owner confirms; Return does
/// nothing, ⌘. confirms, Escape keeps the run going.
Future<bool> confirmCancelRun(
  BuildContext context, {
  required RunJobs runJobs,
  required String title,
  required String engineName,
  required Map<String, String> runners,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierColor: context.xpColors.scrimDefault,
      builder: (_) => CancelRunDialog(
        runJobs: runJobs,
        title: title,
        engineName: engineName,
        runners: runners,
      ),
    ) ??
    false;

class CancelRunDialog extends StatelessWidget {
  const new({
    required this.runJobs,
    required this.title,
    required this.engineName,
    required this.runners,
    super.key,
  });

  final RunJobs runJobs;

  /// What is cancelled, for example `Production release 5.4.1 (3283)`.
  final String title;
  final String engineName;
  final Map<String, String> runners;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final type = context.xpType;
    final now = XpClock.now(context);
    final jobs = runJobs.jobs;
    final running = [
      for (final job in jobs)
        if (job.state == JobState.running) job,
    ];
    final kept = jobs.where((job) => job.state == JobState.succeeded).length;
    final waiting = jobs
        .where(
          (job) =>
              job.state == JobState.queued ||
              job.state == JobState.waitingForApproval ||
              job.state == JobState.interrupted ||
              job.state == JobState.waitingForResume,
        )
        .length;
    void close({required bool confirmed}) =>
        Navigator.of(context).pop(confirmed);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.period, meta: true): () =>
            close(confirmed: true),
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            close(confirmed: false),
      },
      child: Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter):
              DoNothingAndStopPropagationIntent(),
        },
        child: Focus(
          autofocus: true,
          child: Dialog(
            backgroundColor: colors.surfaceOverlay,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(context.xpRadii.lg),
              side: BorderSide(color: colors.borderStrong),
            ),
            child: SizedBox(
              width: 480,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          PhosphorIconsRegular.stopCircle,
                          size: context.xpSizes.iconLg,
                          color: colors.textPrimary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l10n.cancelRunTitle(title),
                            style: type.headline.copyWith(
                              color: colors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    for (final job in running)
                      _Bullet(
                        l10n.cancelRunStops(
                          job.name ?? job.id,
                          job.runnerId == null
                              ? engineName
                              : runners[job.runnerId] ?? job.runnerId!,
                          formatDuration(
                            elapsed(job.startedAt, null, now) ?? Duration.zero,
                          ),
                        ),
                      ),
                    if (kept > 0) _Bullet(l10n.cancelRunKept(kept)),
                    if (waiting > 0)
                      _Bullet(l10n.cancelRunNeverStarts(waiting)),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        XpButton(
                          label: l10n.cancelRunKeep,
                          size: XpButtonSize.large,
                          onPressed: () => close(confirmed: false),
                        ),
                        const SizedBox(width: 8),
                        XpButton(
                          label: l10n.cancelRunConfirm,
                          hint: '⌘.',
                          kind: XpButtonKind.destructive,
                          size: XpButtonSize.large,
                          onPressed: () => close(confirmed: true),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const new(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '•  ',
          style: context.xpType.body.copyWith(
            color: context.xpColors.textSecondary,
          ),
        ),
        Expanded(
          child: Text(
            text,
            style: context.xpType.body.copyWith(
              color: context.xpColors.textPrimary,
            ),
          ),
        ),
      ],
    ),
  );
}

import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/onboarding/bloc/onboarding_bloc.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';
import 'package:xp_macos_services/xp_macos_services.dart';

/// One step of onboarding: a keycap with its [number] (a check once done),
/// what it does, its [result] and its [actions].
class OnboardingStep extends StatelessWidget {
  const new({
    required this.number,
    required this.title,
    required this.body,
    required this.progress,
    required this.actions,
    this.result,
    this.details,
    super.key,
  });

  final int number;
  final String title;
  final String body;
  final StepProgress progress;
  final List<Widget> actions;

  /// The outcome to show, as a status and a sentence.
  final (XpStatus, String)? result;

  /// More below the result (the tool list).
  final Widget? details;

  @override
  Widget build(BuildContext context) {
    final colors = context.xpColors;
    final type = context.xpType;
    final done = progress == StepProgress.done;
    return XpPanel(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: done
                  ? colors.container(XpStatusPair.positive)
                  : colors.surfaceSunken,
              borderRadius: BorderRadius.circular(context.xpRadii.sm),
              border: Border.all(color: colors.borderDefault),
            ),
            child: done
                ? Icon(
                    PhosphorIconsRegular.check,
                    size: context.xpSizes.iconSm,
                    color: colors.onContainer(XpStatusPair.positive),
                    semanticLabel: context.l10n.stepDone,
                  )
                : Text(
                    '$number',
                    style: type.code.copyWith(color: colors.textSecondary),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: type.title.copyWith(color: colors.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: type.body.copyWith(color: colors.textSecondary),
                ),
                if (result case (final status, final text)) ...[
                  const SizedBox(height: 10),
                  XpMessage(status, text),
                ],
                if (details case final details?) ...[
                  const SizedBox(height: 10),
                  details,
                ],
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: actions),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The result of the tool check: each tool, found or missing, with how to
/// get it.
class ToolChecklist extends StatelessWidget {
  const new(this.checks, {super.key});

  final List<ToolCheck> checks;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    final type = context.xpType;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final check in checks)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ConstrainedBox(
                  // Grows with the text size (U6c).
                  constraints: const BoxConstraints(minWidth: 110),
                  child: Text(
                    _name(l10n, check.tool),
                    style: type.bodyStrong.copyWith(color: colors.textPrimary),
                  ),
                ),
                SizedBox(
                  width: 100,
                  child: check.found
                      ? XpStatusLabel(
                          XpStatus.credentialVerified,
                          l10n.toolFound,
                        )
                      : check.tool.required
                      ? XpStatusLabel(XpStatus.scanError, l10n.toolMissing)
                      : XpStatusLabel(XpStatus.scanInfo, l10n.toolOptional),
                ),
                Expanded(
                  child: check.path != null
                      ? XpCode(check.path!, color: colors.textSecondary)
                      : Text(
                          _hint(l10n, check.tool),
                          style: type.caption.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static String _name(AppLocalizations l10n, Tool tool) => switch (tool) {
    Tool.xcode => l10n.toolXcode,
    Tool.git => l10n.toolGit,
    Tool.fvm => l10n.toolFvm,
    Tool.gh => l10n.toolGh,
    Tool.shorebird => l10n.toolShorebird,
  };

  static String _hint(AppLocalizations l10n, Tool tool) => switch (tool) {
    Tool.xcode => l10n.toolXcodeHint,
    Tool.git => l10n.toolGitHint,
    Tool.fvm => l10n.toolFvmHint,
    Tool.gh => l10n.toolGhHint,
    Tool.shorebird => l10n.toolShorebirdHint,
  };
}

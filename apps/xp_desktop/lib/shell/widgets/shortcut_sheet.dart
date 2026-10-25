import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/shell/widgets/command_labels.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';

/// The groups of the menu bar, in its order, each with its commands: the
/// shortcut sheet lists them the same way.
const shortcutGroups = <(String Function(AppLocalizations), List<XpCommand>)>[
  (
    _go,
    [
      XpCommand.palette,
      XpCommand.back,
      XpCommand.forward,
      XpCommand.approvals,
      XpCommand.settings,
    ],
  ),
  (_project, [XpCommand.dispatch, XpCommand.console]),
  (
    _job,
    [
      XpCommand.rerun,
      XpCommand.resume,
      XpCommand.cancel,
      XpCommand.find,
      XpCommand.findNext,
      XpCommand.findPrevious,
      XpCommand.jumpToError,
      XpCommand.followTail,
      XpCommand.timestamps,
      XpCommand.wrap,
    ],
  ),
  (_view, [XpCommand.sidebar, XpCommand.compact, XpCommand.shortcuts]),
];

String _go(AppLocalizations l10n) => l10n.menuGo;
String _project(AppLocalizations l10n) => l10n.menuProject;
String _job(AppLocalizations l10n) => l10n.menuJob;
String _view(AppLocalizations l10n) => l10n.menuView;

/// ⌘/: every shortcut of the keyboard guide, by menu, with keycaps.
Future<void> showShortcutSheet(BuildContext context) => showDialog<void>(
  context: context,
  barrierColor: context.xpColors.scrimDefault,
  builder: (_) => const ShortcutSheet(),
);

class ShortcutSheet extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.xpColors;
    return Dialog(
      backgroundColor: colors.surfaceOverlay,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.xpRadii.lg),
        side: BorderSide(color: colors.borderStrong),
      ),
      child: SizedBox(
        width: 560,
        height: 600,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: XpPageHeader(
                title: l10n.shortcutsTitle,
                actions: [
                  XpButton(
                    label: l10n.shortcutsClose,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const XpHairline(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (title, commands) in shortcutGroups) ...[
                      XpSectionLabel(title(l10n)),
                      const SizedBox(height: 6),
                      for (final command in commands)
                        _Row(commandLabel(l10n, command), command.keys),
                      if (commands.contains(XpCommand.settings))
                        _Row(l10n.shortcutsProjects, '⌘1 – ⌘9'),
                      const SizedBox(height: 16),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const new(this.label, this.keys);

  final String label;
  final String keys;

  @override
  Widget build(BuildContext context) {
    final colors = context.xpColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: context.xpType.body.copyWith(color: colors.textPrimary),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: colors.surfaceSunken,
              borderRadius: BorderRadius.circular(context.xpRadii.sm),
              border: Border.all(color: colors.borderDefault),
            ),
            child: Text(
              keys,
              style: context.xpType.code.copyWith(color: colors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

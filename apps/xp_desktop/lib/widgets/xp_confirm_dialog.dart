import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/xp_button.dart';

/// Asks before a destructive action: [title] names the object and
/// [points] say what happens. `true` when the owner presses [confirm];
/// Return does nothing, Escape and [keep] change nothing.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required List<String> points,
  required String keep,
  required String confirm,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierColor: context.xpColors.scrimDefault,
      builder: (_) => _ConfirmDialog(
        key: confirmDialogKey,
        title: title,
        points: points,
        keep: keep,
        confirm: confirm,
      ),
    ) ??
    false;

/// The key of the dialog [confirmAction] shows, for finding it.
const confirmDialogKey = Key('xp.confirmAction');

/// The dialog of [confirmAction]; it pops `true` or `false`.
class _ConfirmDialog extends StatelessWidget {
  const new({
    required this.title,
    required this.points,
    required this.keep,
    required this.confirm,
    super.key,
  });

  final String title;
  final List<String> points;
  final String keep;
  final String confirm;

  @override
  Widget build(BuildContext context) {
    final colors = context.xpColors;
    final type = context.xpType;
    void close({required bool confirmed}) =>
        Navigator.of(context).pop(confirmed);
    return CallbackShortcuts(
      bindings: {
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
              width: 460,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: type.headline.copyWith(color: colors.textPrimary),
                    ),
                    const SizedBox(height: 14),
                    for (final point in points)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          '•  $point',
                          style: type.body.copyWith(color: colors.textPrimary),
                        ),
                      ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        XpButton(
                          label: keep,
                          size: XpButtonSize.large,
                          onPressed: () => close(confirmed: false),
                        ),
                        const SizedBox(width: 8),
                        XpButton(
                          label: confirm,
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

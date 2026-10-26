import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/toast/cubit/toast_cubit.dart';
import 'package:xp_desktop/widgets/xp_button.dart';

/// One item of a context menu: what it says and does. A [destructive] item
/// is in the negative colour (UX-08).
class XpMenuAction {
  const new(
    this.label,
    VoidCallback this.onSelected, {
    this.destructive = false,
  }) : copies = null;

  /// Copies [copies] and says so in a toast.
  const new copy(this.label, String this.copies)
    : onSelected = null,
      destructive = false;

  final String label;
  final VoidCallback? onSelected;
  final String? copies;
  final bool destructive;
}

/// Shows [actions] as a context menu at [position], where the owner
/// right-clicked, and does the one chosen.
Future<void> showXpContextMenu(
  BuildContext context,
  Offset position,
  List<XpMenuAction> actions,
) async {
  final colors = context.xpColors;
  final type = context.xpType;
  final toasts = context.read<ToastCubit>();
  final l10n = context.l10n;
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final chosen = await showMenu<XpMenuAction>(
    context: context,
    position: RelativeRect.fromRect(
      position & Size.zero,
      Offset.zero & overlay.size,
    ),
    items: [
      for (final action in actions)
        PopupMenuItem(
          value: action,
          height: context.xpSizes.rowDefault,
          child: Text(
            action.label,
            style: type.body.copyWith(
              color: action.destructive
                  ? colors.negativeDefault
                  : colors.textPrimary,
            ),
          ),
        ),
    ],
  );
  if (chosen == null) return;
  if (chosen.copies case final copies?) {
    await Clipboard.setData(ClipboardData(text: copies));
    toasts.show(l10n.copiedValue(copies));
    return;
  }
  chosen.onSelected?.call();
}

/// A button that opens [actions] as a menu under itself: the actions of a
/// row that are not its main one, with Delete last and destructive (U6c).
class XpMenuButton extends StatelessWidget {
  const new({required this.label, required this.actions, super.key});

  /// What it is called, for example `More`.
  final String label;

  /// `null` disables it.
  final List<XpMenuAction>? actions;

  @override
  Widget build(BuildContext context) {
    final actions = this.actions;
    return Builder(
      builder: (context) => XpButton(
        label: label,
        icon: PhosphorIconsRegular.dotsThree,
        size: XpButtonSize.small,
        kind: XpButtonKind.tertiary,
        onPressed: actions == null
            ? null
            : () {
                final box = context.findRenderObject()! as RenderBox;
                unawaited(
                  showXpContextMenu(
                    context,
                    box.localToGlobal(box.size.bottomLeft(Offset.zero)),
                    actions,
                  ),
                );
              },
      ),
    );
  }
}

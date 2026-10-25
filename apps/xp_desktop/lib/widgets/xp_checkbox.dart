import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/theme/theme.dart';

/// A checkbox with its [label] (`radius.xs`, `color.border.strong` while
/// off, the accent while on). Clicking the row, Space or Return toggles it.
class XpCheckbox extends StatelessWidget {
  const new({
    required this.label,
    required this.value,
    required this.onChanged,
    this.detail,
    super.key,
  });

  final String label;
  final bool value;

  /// A second line under [label].
  final String? detail;

  /// `null` disables it.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.xpColors;
    final type = context.xpType;
    final onChanged = this.onChanged;
    void toggle() => onChanged?.call(!value);
    return Semantics(
      checked: value,
      enabled: onChanged != null,
      label: label,
      excludeSemantics: true,
      child: FocusableActionDetector(
        enabled: onChanged != null,
        mouseCursor: onChanged == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) => toggle(),
          ),
        },
        child: GestureDetector(
          onTap: onChanged == null ? null : toggle,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 16,
                  height: 16,
                  margin: const EdgeInsets.only(top: 2),
                  decoration: BoxDecoration(
                    color: value ? colors.accentDefault : colors.surfaceRaised,
                    borderRadius: BorderRadius.circular(context.xpRadii.xs),
                    border: Border.all(
                      color: value ? colors.accentDefault : colors.borderStrong,
                    ),
                  ),
                  child: value
                      ? Icon(
                          PhosphorIconsRegular.check,
                          size: 12,
                          color: colors.textOnAccent,
                        )
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: type.body.copyWith(
                          color: onChanged == null
                              ? colors.textTertiary
                              : colors.textPrimary,
                        ),
                      ),
                      if (detail case final detail?)
                        Text(
                          detail,
                          style: type.caption.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

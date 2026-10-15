import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/theme/theme.dart';

/// A segmented control (`size.control.md`): the selected segment sits on
/// `surface.raised` with a hairline inside a sunken well.
class XpSegmented<T> extends StatelessWidget {
  const new({
    required this.value,
    required this.values,
    required this.labelOf,
    required this.onChanged,
    super.key,
  });

  final T value;
  final List<T> values;
  final String Function(T value) labelOf;

  /// `null` disables it.
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.xpColors;
    final radius = context.xpRadii.md;
    return Container(
      height: context.xpSizes.controlMd,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: colors.surfaceSunken,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: colors.borderDefault),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final item in values)
            _Segment(
              label: labelOf(item),
              selected: item == value,
              onTap: onChanged == null ? null : () => onChanged!(item),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const new({required this.label, required this.selected, this.onTap});

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.xpColors;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: context.xpMotion.durationBase,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? colors.surfaceRaised : Colors.transparent,
              borderRadius: BorderRadius.circular(context.xpRadii.sm),
              border: Border.all(
                color: selected ? colors.borderDefault : Colors.transparent,
              ),
            ),
            child: Text(
              label,
              style:
                  (selected ? context.xpType.bodyStrong : context.xpType.body)
                      .copyWith(
                        color: onTap == null
                            ? colors.textDisabled
                            : selected
                            ? colors.textPrimary
                            : colors.textSecondary,
                      ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A chip that turns on and off (`size.control.sm`, `radius.sm`): on is the
/// accent container, off a hairline.
class XpChip extends StatelessWidget {
  const new({
    required this.label,
    required this.selected,
    required this.onChanged,
    this.icon,
    super.key,
  });

  final String label;
  final bool selected;
  final IconData? icon;

  /// `null` disables it.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.xpColors;
    final ink = onChanged == null
        ? colors.textDisabled
        : selected
        ? colors.accentOnContainer
        : colors.textPrimary;
    return Semantics(
      button: true,
      toggled: selected,
      label: label,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: onChanged == null
            ? MouseCursor.defer
            : SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onChanged == null ? null : () => onChanged!(!selected),
          child: AnimatedContainer(
            duration: context.xpMotion.durationFast,
            height: context.xpSizes.controlSm,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: selected ? colors.accentContainer : colors.surfaceRaised,
              borderRadius: BorderRadius.circular(context.xpRadii.sm),
              border: Border.all(
                color: selected ? colors.accentDefault : colors.borderDefault,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon case final icon?) ...[
                  Icon(icon, size: context.xpSizes.iconSm, color: ink),
                  const SizedBox(width: 4),
                ],
                Text(label, style: context.xpType.body.copyWith(color: ink)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

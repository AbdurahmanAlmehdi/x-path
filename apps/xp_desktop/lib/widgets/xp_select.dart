import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/theme/theme.dart';

/// A pop-up button: the [value]'s label in a field-shaped control
/// (`size.control.md`) that opens a menu of [values].
class XpSelect<T> extends StatelessWidget {
  const new({
    required this.value,
    required this.values,
    required this.labelOf,
    required this.onChanged,
    this.code = false,
    super.key,
  });

  final T value;
  final List<T> values;
  final String Function(T value) labelOf;

  /// `null` disables it.
  final ValueChanged<T>? onChanged;

  /// Sets the labels in `type.code`.
  final bool code;

  @override
  Widget build(BuildContext context) {
    final colors = context.xpColors;
    final style = (code ? context.xpType.code : context.xpType.body).copyWith(
      color: onChanged == null ? colors.textDisabled : colors.textPrimary,
    );
    return PopupMenuButton<T>(
      enabled: onChanged != null,
      tooltip: '',
      initialValue: value,
      position: PopupMenuPosition.under,
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final item in values)
          PopupMenuItem<T>(
            value: item,
            height: context.xpSizes.rowDefault,
            child: Text(labelOf(item), style: style),
          ),
      ],
      child: Container(
        height: context.xpSizes.controlMd,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: colors.surfaceRaised,
          borderRadius: BorderRadius.circular(context.xpRadii.md),
          border: Border.all(color: colors.borderDefault),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                labelOf(value),
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              PhosphorIconsRegular.caretDown,
              size: context.xpSizes.iconXs,
              color: colors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

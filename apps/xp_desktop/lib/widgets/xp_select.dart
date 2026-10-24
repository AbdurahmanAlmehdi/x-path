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
    final onChanged = this.onChanged;
    final colors = context.xpColors;
    final style = (code ? context.xpType.code : context.xpType.body).copyWith(
      color: onChanged == null ? colors.textDisabled : colors.textPrimary,
    );
    // The menu picks an index: it would not report a pick of `null`.
    return PopupMenuButton<int>(
      enabled: onChanged != null,
      tooltip: '',
      initialValue: values.indexOf(value),
      position: PopupMenuPosition.under,
      onSelected: onChanged == null
          ? null
          : (index) => onChanged(values[index]),
      itemBuilder: (context) => [
        for (final (index, item) in values.indexed)
          PopupMenuItem<int>(
            value: index,
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

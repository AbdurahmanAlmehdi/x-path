import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';

/// An [XpTextField] bound to a value of the document: it shows [value] and
/// reports each change. While it has focus the owner's text stands (the
/// document may write it differently, `'a'` as `a`); a new [value] shows
/// while the field does not have focus, and when it loses it.
///
/// With [completions], the name being typed at the end is completed from
/// them, as in `flavor.p` to `flavor.prod`.
class BoundTextField extends StatefulWidget {
  const new({
    required this.value,
    required this.onChanged,
    this.label,
    this.hint,
    this.code = false,
    this.maxLines = 1,
    this.enabled = true,
    this.completions = const [],
    super.key,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String? label;
  final String? hint;
  final bool code;
  final int maxLines;
  final bool enabled;
  final List<String> completions;

  @override
  State<BoundTextField> createState() => _BoundTextFieldState();
}

class _BoundTextFieldState extends State<BoundTextField> {
  late final _controller = TextEditingController(text: widget.value);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _show(widget.value);
    });
  }

  @override
  void didUpdateWidget(BoundTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus) _show(widget.value);
  }

  void _show(String value) {
    if (value != _controller.text) _controller.text = value;
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Widget _field() => XpTextField(
    label: widget.label,
    controller: _controller,
    focusNode: _focus,
    hint: widget.hint,
    code: widget.code,
    maxLines: widget.maxLines,
    enabled: widget.enabled,
    onChanged: widget.onChanged,
  );

  @override
  Widget build(BuildContext context) {
    if (widget.completions.isEmpty) return _field();
    final colors = context.xpColors;
    return RawAutocomplete<Completion>(
      textEditingController: _controller,
      focusNode: _focus,
      optionsBuilder: (value) => completionsOf(value.text, widget.completions),
      displayStringForOption: (option) => option.text,
      onSelected: (option) => widget.onChanged(option.text),
      fieldViewBuilder: (context, controller, focus, submit) => _field(),
      optionsViewBuilder: (context, select, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          color: colors.surfaceOverlay,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(context.xpRadii.md),
            side: BorderSide(color: colors.borderStrong),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320, maxHeight: 240),
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 4),
              shrinkWrap: true,
              children: [
                for (final option in options)
                  InkWell(
                    onTap: () => select(option),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: XpCode(option.path),
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

/// A completion of a field: the path offered, and the text the field has
/// once it is taken.
typedef Completion = ({String path, String text});

final _nameAtEnd = RegExp(r'[A-Za-z_][A-Za-z0-9_.]*$');

/// The [completions] that complete the name at the end of [text], at most
/// eight: `flavor.p` gives `flavor.prod`; nothing once the name is whole.
List<Completion> completionsOf(String text, List<String> completions) {
  final match = _nameAtEnd.firstMatch(text);
  if (match == null) return const [];
  final name = match[0]!;
  return [
    for (final path in completions)
      if (path.startsWith(name) && path != name)
        (path: path, text: '${text.substring(0, match.start)}$path'),
  ].take(8).toList();
}

/// A small icon-only action in a row (`size.control.sm`) with a tooltip
/// that names it; `null` [onPressed] disables it.
class RowAction extends StatelessWidget {
  const new({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.xpColors;
    final size = context.xpSizes.controlSm;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: onPressed != null,
        label: tooltip,
        excludeSemantics: true,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(context.xpRadii.md),
          child: SizedBox.square(
            dimension: size,
            child: Icon(
              icon,
              size: context.xpSizes.iconSm,
              color: onPressed == null
                  ? colors.textDisabled
                  : colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Move earlier, move later and remove, for the item at [index] of
/// [count].
class OrderActions extends StatelessWidget {
  const new({
    required this.index,
    required this.count,
    required this.onMove,
    required this.onRemove,
    required this.earlier,
    required this.later,
    required this.remove,
    this.enabled = true,
    super.key,
  });

  final int index;
  final int count;
  final ValueChanged<int> onMove;
  final VoidCallback onRemove;
  final String earlier;
  final String later;
  final String remove;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      RowAction(
        icon: PhosphorIconsRegular.arrowUp,
        tooltip: earlier,
        onPressed: enabled && index > 0 ? () => onMove(-1) : null,
      ),
      RowAction(
        icon: PhosphorIconsRegular.arrowDown,
        tooltip: later,
        onPressed: enabled && index < count - 1 ? () => onMove(1) : null,
      ),
      RowAction(
        icon: PhosphorIconsRegular.trash,
        tooltip: remove,
        onPressed: enabled ? onRemove : null,
      ),
    ],
  );
}

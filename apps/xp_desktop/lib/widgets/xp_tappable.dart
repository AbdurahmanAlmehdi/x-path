import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/theme/theme.dart';

/// A row, cell or node that does [onTap] on a click: it takes the focus with
/// Tab (↑ and ↓ move between rows), does [onTap] on Return or Space, draws
/// the focus ring, and is a button with [label] for a screen reader (U6c).
/// [onSecondaryTap] gets the position of a right click, for a context menu.
class XpTappable extends StatefulWidget {
  const new({
    required this.onTap,
    required this.child,
    this.label,
    this.selected = false,
    this.onHover,
    this.onSecondaryTap,
    this.radius,
    super.key,
  });

  /// `null` leaves it inert and out of the focus order.
  final VoidCallback? onTap;
  final Widget child;

  /// What a screen reader says; the child's own semantics when `null`.
  final String? label;
  final bool selected;
  final ValueChanged<bool>? onHover;
  final ValueChanged<Offset>? onSecondaryTap;

  /// The corner radius of the focus ring; `radius.md` by default.
  final double? radius;

  @override
  State<XpTappable> createState() => _XpTappableState();
}

class _XpTappableState extends State<XpTappable> {
  var _focused = false;

  @override
  Widget build(BuildContext context) {
    final onTap = widget.onTap;
    final label = widget.label;
    return Semantics(
      button: true,
      selected: widget.selected,
      enabled: onTap != null,
      label: label,
      excludeSemantics: label != null,
      child: FocusableActionDetector(
        enabled: onTap != null,
        mouseCursor: onTap == null
            ? MouseCursor.defer
            : SystemMouseCursors.click,
        onShowHoverHighlight: widget.onHover,
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              onTap?.call();
              return null;
            },
          ),
        },
        child: GestureDetector(
          onTap: onTap,
          onSecondaryTapUp: widget.onSecondaryTap == null
              ? null
              : (details) => widget.onSecondaryTap!(details.globalPosition),
          behavior: HitTestBehavior.opaque,
          child: Container(
            foregroundDecoration: _focused
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(
                      widget.radius ?? context.xpRadii.md,
                    ),
                    border: Border.all(
                      color: context.xpColors.focusRing,
                      width: context.xpBorders.widthFocus,
                    ),
                  )
                : null,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/xp_spinner.dart';

/// The kinds of button of the Run Sheet: one [primary] per screen,
/// [secondary] and [tertiary] for the rest, [warning] only on the needs-you
/// bar, [destructive] for the confirming button of a destructive sheet.
enum XpButtonKind { primary, secondary, tertiary, warning, destructive }

/// How tall a button is: `size.control.sm` in rows, `md` by default, `lg` in
/// sheet and dialog footers.
enum XpButtonSize { small, medium, large }

/// A Run Sheet button: colour changes on hover and press, no ripple, a focus
/// ring for the keyboard, an optional icon and shortcut hint.
class XpButton extends StatefulWidget {
  const new({
    required this.label,
    required this.onPressed,
    this.kind = XpButtonKind.secondary,
    this.size = XpButtonSize.medium,
    this.icon,
    this.hint,
    this.busy = false,
    this.tooltip,
    super.key,
  });

  final String label;

  /// `null` disables the button.
  final VoidCallback? onPressed;
  final XpButtonKind kind;
  final XpButtonSize size;
  final IconData? icon;

  /// A shortcut shown after the label, for example `⌘N`.
  final String? hint;

  /// Shows a running arc instead of the icon and ignores presses.
  final bool busy;

  /// Shown on hover; for example why the button is disabled.
  final String? tooltip;

  @override
  State<XpButton> createState() => _XpButtonState();
}

class _XpButtonState extends State<XpButton> {
  var _hovered = false;
  var _pressed = false;
  var _focused = false;

  bool get _enabled => widget.onPressed != null && !widget.busy;

  void _activate() {
    if (_enabled) widget.onPressed!();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.xpColors;
    final type = context.xpType;
    final sizes = context.xpSizes;
    final radii = context.xpRadii;
    final (fill, hover, press, ink, border) = switch (widget.kind) {
      XpButtonKind.primary => (
        colors.accentDefault,
        colors.accentHover,
        colors.accentPressed,
        colors.textOnAccent,
        null,
      ),
      XpButtonKind.warning => (
        colors.warningDefault,
        colors.warningHover,
        colors.warningPressed,
        colors.warningOnWarning,
        null,
      ),
      XpButtonKind.destructive => (
        colors.negativeDefault,
        colors.negativeHover,
        colors.negativePressed,
        colors.negativeOnNegative,
        null,
      ),
      XpButtonKind.secondary => (
        colors.surfaceRaised,
        colors.surfaceHover,
        colors.surfacePressed,
        colors.textPrimary,
        colors.borderDefault,
      ),
      XpButtonKind.tertiary => (
        Colors.transparent,
        colors.surfaceHover,
        colors.surfacePressed,
        colors.textPrimary,
        null,
      ),
    };
    final background = !_enabled
        ? (widget.kind == XpButtonKind.tertiary
              ? Colors.transparent
              : colors.surfaceSunken)
        : _pressed
        ? press
        : _hovered
        ? hover
        : fill;
    final foreground = _enabled ? ink : colors.textDisabled;
    final height = switch (widget.size) {
      XpButtonSize.small => sizes.controlSm,
      XpButtonSize.medium => sizes.controlMd,
      XpButtonSize.large => sizes.controlLg,
    };
    final iconSize = widget.size == XpButtonSize.small
        ? sizes.iconSm
        : sizes.iconMd;
    final leading = widget.busy
        ? XpSpinner(
            icon: PhosphorIconsRegular.circleNotch,
            size: iconSize,
            color: foreground,
          )
        : widget.icon == null
        ? null
        : Icon(widget.icon, size: iconSize, color: foreground);

    Widget button = AnimatedContainer(
      duration: context.xpMotion.durationFast,
      height: height,
      padding: EdgeInsets.symmetric(
        horizontal: widget.size == XpButtonSize.small ? 8 : 12,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(radii.md),
        border: border == null || !_enabled ? null : Border.all(color: border),
      ),
      foregroundDecoration: _focused
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(radii.md),
              border: Border.all(
                color: colors.focusRing,
                width: context.xpBorders.widthFocus,
              ),
            )
          : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[leading, const SizedBox(width: 6)],
          Text(
            widget.label,
            style: type.bodyStrong.copyWith(color: foreground),
          ),
          if (widget.hint case final hint?) ...[
            const SizedBox(width: 8),
            Text(
              hint,
              style: type.code.copyWith(
                color:
                    widget.kind == XpButtonKind.primary ||
                        widget.kind == XpButtonKind.warning ||
                        widget.kind == XpButtonKind.destructive
                    ? foreground
                    : colors.textTertiary,
              ),
            ),
          ],
        ],
      ),
    );

    // A busy button keeps the focus it had, so Tab goes on from it (U6c).
    button = FocusableActionDetector(
      enabled: widget.onPressed != null,
      mouseCursor: _enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onShowHoverHighlight: (value) => setState(() => _hovered = value),
      onShowFocusHighlight: (value) => setState(() => _focused = value),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _activate();
            return null;
          },
        ),
      },
      child: GestureDetector(
        onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: _enabled ? _activate : null,
        child: Semantics(
          button: true,
          enabled: _enabled,
          label: widget.label,
          excludeSemantics: true,
          child: button,
        ),
      ),
    );
    if (widget.tooltip case final tooltip?) {
      button = Tooltip(message: tooltip, child: button);
    }
    return button;
  }
}

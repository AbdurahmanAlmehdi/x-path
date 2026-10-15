import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/xp_spinner.dart';

/// The icon of [status] in its pair's on-container colour; the running arc
/// and the reconnecting arrows turn.
class XpStatusIcon extends StatelessWidget {
  const new(this.status, {this.size, super.key});

  final XpStatus status;

  /// Defaults to `size.icon.sm`.
  final double? size;

  @override
  Widget build(BuildContext context) {
    final color = context.xpColors.onContainer(status.pair);
    final iconSize = size ?? context.xpSizes.iconSm;
    return switch (status.motion) {
      XpStatusMotion.none => Icon(status.icon, size: iconSize, color: color),
      XpStatusMotion.spin => XpSpinner(
        icon: status.icon,
        size: iconSize,
        color: color,
      ),
      XpStatusMotion.turn => XpSpinner(
        icon: status.icon,
        size: iconSize,
        color: color,
        slow: true,
      ),
    };
  }
}

/// Inline status: icon and [label] in the pair's on-container colour, no
/// container (table rows, sidebar).
class XpStatusLabel extends StatelessWidget {
  const new(this.status, this.label, {this.style, super.key});

  final XpStatus status;

  /// The localized label.
  final String label;

  /// Defaults to `type.caption`.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      XpStatusIcon(status),
      const SizedBox(width: 4),
      Flexible(
        child: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: (style ?? context.xpType.caption).copyWith(
            color: context.xpColors.onContainer(status.pair),
          ),
        ),
      ),
    ],
  );
}

/// A badge: icon and [label] on the pair's container (`radius.sm`).
class XpBadge extends StatelessWidget {
  const new(this.status, this.label, {super.key});

  final XpStatus status;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: context.xpColors.container(status.pair),
      borderRadius: BorderRadius.circular(context.xpRadii.sm),
    ),
    child: XpStatusLabel(status, label),
  );
}

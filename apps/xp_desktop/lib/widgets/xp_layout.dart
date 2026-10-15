import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/theme/theme.dart';

/// A section or column label: `type.label`, mono caps, 0.06em tracking,
/// secondary text. Never a sentence.
class XpSectionLabel extends StatelessWidget {
  const new(this.text, {this.color, super.key});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final style = context.xpType.label;
    return Text(
      text.toUpperCase(),
      style: style.copyWith(
        color: color ?? context.xpColors.textSecondary,
        letterSpacing: (style.fontSize ?? 11) * 0.06,
      ),
    );
  }
}

/// A panel on the window: `surface.raised`, a hairline and `radius.md`. No
/// shadow, and never a panel inside a panel.
class XpPanel extends StatelessWidget {
  const new({required this.child, this.padding, super.key});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: context.xpColors.surfaceRaised,
      borderRadius: BorderRadius.circular(context.xpRadii.md),
      border: Border.all(color: context.xpColors.borderDefault),
    ),
    child: child,
  );
}

/// A hairline rule in `color.border.default`.
class XpHairline extends StatelessWidget {
  const new({this.vertical = false, super.key});

  final bool vertical;

  @override
  Widget build(BuildContext context) => Container(
    width: vertical ? 1 : null,
    height: vertical ? null : 1,
    color: context.xpColors.borderDefault,
  );
}

/// An identifier (path, bundle ID, URL, version) in `type.code`, selectable.
class XpCode extends StatelessWidget {
  const new(this.text, {this.color, this.size, super.key});

  final String text;
  final Color? color;
  final double? size;

  @override
  Widget build(BuildContext context) => SelectableText(
    text,
    maxLines: 1,
    style: context.xpType.code.copyWith(
      color: color ?? context.xpColors.textPrimary,
      fontSize: size,
    ),
  );
}

/// The header of a page inside the content area: `type.headline` and a
/// secondary line, with [actions] at the trailing end.
class XpPageHeader extends StatelessWidget {
  const new({
    required this.title,
    this.subtitle,
    this.actions = const [],
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: context.xpType.headline.copyWith(
                color: context.xpColors.textPrimary,
              ),
            ),
            if (subtitle case final subtitle?) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: context.xpType.body.copyWith(
                  color: context.xpColors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
      for (final action in actions) ...[const SizedBox(width: 8), action],
    ],
  );
}

/// An inline message under a form or step: icon and text in a status
/// colour, no container.
class XpMessage extends StatelessWidget {
  const new(this.status, this.text, {super.key});

  final XpStatus status;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = context.xpColors.onContainer(status.pair);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Icon(status.icon, size: context.xpSizes.iconSm, color: color),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text, style: context.xpType.body.copyWith(color: color)),
        ),
      ],
    );
  }
}

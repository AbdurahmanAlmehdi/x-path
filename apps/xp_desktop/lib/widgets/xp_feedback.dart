import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/xp_button.dart';
import 'package:xp_desktop/widgets/xp_layout.dart';

/// Why something could not be loaded, then Retry. [message] is the engine's
/// own words with what it says to do, or a plain sentence for an error
/// nobody expected (`errorMessage`), never the error's raw text.
class XpErrorState extends StatelessWidget {
  const new(this.message, {required this.onRetry, super.key});

  final String message;

  /// Loads it again.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      XpMessage.error(message),
      const SizedBox(height: 10),
      XpButton(
        label: context.l10n.retry,
        icon: PhosphorIconsRegular.arrowClockwise,
        size: XpButtonSize.small,
        onPressed: onRetry,
      ),
    ],
  );
}

/// What shows while a page or section loads: [rows] bars of
/// `surface.sunken`, as wide as a list's lines. They stand still, so
/// nothing moves under Reduce Motion.
class XpLoading extends StatelessWidget {
  const new({this.rows = 6, super.key});

  final int rows;

  static const _widths = [0.6, 0.85, 0.4];

  @override
  Widget build(BuildContext context) => Semantics(
    label: context.l10n.loading,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var row = 0; row < rows; row++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: FractionallySizedBox(
              widthFactor: _widths[row % _widths.length],
              child: Container(
                height: 12,
                decoration: BoxDecoration(
                  color: context.xpColors.surfaceSunken,
                  borderRadius: BorderRadius.circular(context.xpRadii.xs),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

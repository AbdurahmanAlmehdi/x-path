import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/theme/xp_tokens.dart';

export 'phosphor_icons.dart';
export 'xp_tokens.dart';

/// The app's theme for [brightness]: `xpTheme` from the Run Sheet tokens,
/// plus what the Material widgets the app still uses (text fields, menus,
/// tooltips, scroll bars) need to look like the rest. No ripples: macOS
/// controls change colour on hover and press instead.
ThemeData appTheme(Brightness brightness, {bool reduceMotion = false}) {
  final base = xpTheme(brightness, reduceMotion: reduceMotion);
  final colors = base.extension<XpColors>()!;
  final type = base.extension<XpTypography>()!;
  final radii = base.extension<XpRadii>()!;
  return base.copyWith(
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: colors.surfaceHover,
    canvasColor: colors.surfaceOverlay,
    dividerColor: colors.borderDefault,
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: colors.accentDefault,
      onPrimary: colors.textOnAccent,
      secondary: colors.accentDefault,
      onSecondary: colors.textOnAccent,
      error: colors.negativeDefault,
      onError: colors.negativeOnNegative,
      surface: colors.surfaceRaised,
      onSurface: colors.textPrimary,
      outline: colors.borderDefault,
    ),
    textTheme: TextTheme(
      bodyMedium: type.body.copyWith(color: colors.textPrimary),
      bodySmall: type.caption.copyWith(color: colors.textSecondary),
      titleMedium: type.title.copyWith(color: colors.textPrimary),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: colors.surfaceInverse,
        borderRadius: BorderRadius.circular(radii.sm),
      ),
      textStyle: type.caption.copyWith(color: colors.textOnInverse),
      waitDuration: const Duration(milliseconds: 500),
    ),
    textSelectionTheme: TextSelectionThemeData(
      selectionColor: colors.selectionDefault,
      cursorColor: colors.accentDefault,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(colors.borderStrong),
      radius: Radius.circular(radii.full),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: colors.surfaceOverlay,
      elevation: brightness == Brightness.dark ? 0 : 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radii.lg),
        side: BorderSide(color: colors.borderDefault),
      ),
      textStyle: type.body.copyWith(color: colors.textPrimary),
    ),
  );
}

/// The token families `XpThemeX` does not reach.
extension XpThemeMore on BuildContext {
  XpBorders get xpBorders => Theme.of(this).extension<XpBorders>()!;
  XpElevation get xpElevation => Theme.of(this).extension<XpElevation>()!;
}

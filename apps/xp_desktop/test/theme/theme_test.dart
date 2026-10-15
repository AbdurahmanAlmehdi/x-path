import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/theme/theme.dart';

void main() {
  group('appTheme', () {
    test('carries every token family, in both themes', () {
      for (final brightness in Brightness.values) {
        final theme = appTheme(brightness);
        expect(theme.brightness, brightness);
        expect(theme.extension<XpColors>(), isNotNull);
        expect(theme.extension<XpTypography>(), XpTypography.standard);
        expect(theme.extension<XpSizes>(), XpSizes.standard);
        expect(
          theme.scaffoldBackgroundColor,
          brightness == Brightness.dark
              ? XpColors.dark.surfaceWindow
              : XpColors.light.surfaceWindow,
        );
      }
      expect(
        appTheme(Brightness.light, reduceMotion: true).extension<XpMotion>(),
        XpMotion.reduced,
      );
    });

    test('the theme animates between light and dark', () {
      // ThemeData.lerp interpolates every extension: the window animates
      // when macOS switches appearance.
      final light = appTheme(Brightness.light);
      final dark = appTheme(Brightness.dark);
      final halfway = ThemeData.lerp(light, dark, 0.5);
      expect(halfway.extension<XpColors>(), isNot(XpColors.light));
      expect(ThemeData.lerp(light, light, 1).extension<XpColors>(), isNotNull);
      expect(
        xpTheme(Brightness.dark, compact: true).extension<XpSizes>(),
        XpSizes.compact,
      );
    });

    test('every token family copies itself', () {
      final families = <ThemeExtension<dynamic>>[
        XpColors.light,
        XpTypography.standard,
        XpSpacing.standard,
        XpRadii.standard,
        XpBorders.standard,
        XpElevation.light,
        XpSizes.standard,
        XpMotion.standard,
        XpWindow.standard,
      ];
      for (final family in families) {
        expect(family.copyWith().runtimeType, family.runtimeType);
        expect(family.lerp(null, 0.5), same(family));
        expect(family.lerp(family, 0.5).runtimeType, family.runtimeType);
      }
    });

    test('statuses name their pair colours', () {
      for (final pair in XpStatusPair.values) {
        expect(XpColors.light.container(pair), isA<Color>());
        expect(XpColors.dark.onContainer(pair), isA<Color>());
      }
      expect(XpStatus.jobRunning.motion, XpStatusMotion.spin);
    });
  });

  testWidgets('the context reaches every token family', (tester) async {
    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme(Brightness.light),
        home: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(captured.xpColors, XpColors.light);
    expect(captured.xpType, XpTypography.standard);
    expect(captured.xpSpace, XpSpacing.standard);
    expect(captured.xpRadii, XpRadii.standard);
    expect(captured.xpSizes, XpSizes.standard);
    expect(captured.xpMotion, XpMotion.standard);
    expect(captured.xpBorders, XpBorders.standard);
    expect(captured.xpElevation, XpElevation.light);
  });
}

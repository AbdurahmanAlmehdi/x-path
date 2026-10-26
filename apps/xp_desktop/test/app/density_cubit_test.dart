import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/app/app.dart';
import 'package:xp_desktop/theme/theme.dart';

void main() {
  test('DensityCubit switches compact rows and keeps the choice', () async {
    final preferences = AppPreferences();
    final cubit = DensityCubit(preferences);

    expect(cubit.state, isFalse);
    await cubit.toggle();
    expect(cubit.state, isTrue);
    expect(preferences.compactRows, isTrue);
    expect(DensityCubit(preferences).state, isTrue);
    await cubit.close();
  });

  test('the theme follows compact rows, Reduce Motion and the text size', () {
    XpSizes sizes(ThemeData theme) => theme.extension<XpSizes>()!;
    final standard = appTheme(Brightness.light);

    expect(
      sizes(appTheme(Brightness.light, compact: true)).rowDefault,
      lessThan(sizes(standard).rowDefault),
    );
    expect(
      sizes(appTheme(Brightness.light, textScale: 2)).rowDefault,
      sizes(standard).rowDefault * 2,
    );
    expect(
      appTheme(Brightness.dark, reduceMotion: true).extension<XpMotion>(),
      XpMotion.reduced,
    );
  });
}

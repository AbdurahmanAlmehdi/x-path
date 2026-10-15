@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/tests/tests.dart';

import '../helpers/load_fonts.dart';
import 'tests_page_test.dart' show TestsHarness;

void main() {
  setUpAll(loadAppFonts);

  for (final brightness in Brightness.values) {
    testWidgets('the tests view, ${brightness.name}', (tester) async {
      await TestsHarness().pump(tester, brightness: brightness);
      await expectLater(
        find.byType(TestsPage),
        matchesGoldenFile('goldens/tests_${brightness.name}.png'),
      );
    });
  }
}

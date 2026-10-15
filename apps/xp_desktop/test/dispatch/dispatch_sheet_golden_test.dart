@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/load_fonts.dart';
import 'dispatch_harness.dart';

void main() {
  setUpAll(() async {
    registerDispatchFallbacks();
    await loadAppFonts();
  });

  testWidgets('the dispatch sheet', (tester) async {
    await DispatchHarness().open(tester);
    await expectLater(
      find.byType(Dialog),
      matchesGoldenFile('goldens/dispatch_sheet.png'),
    );
  });
}

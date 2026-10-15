@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_desktop/project_overview/view/project_overview_page.dart';

import '../helpers/job_fixtures.dart';
import '../helpers/load_fonts.dart';
import '../helpers/release_fixtures.dart';
import 'overview_harness.dart';

void main() {
  setUpAll(() async {
    registerFallbackValue(runningRun().run);
    await loadAppFonts();
  });

  for (final brightness in Brightness.values) {
    testWidgets('the overview, ${brightness.name}', (tester) async {
      await OverviewHarness().pump(tester, brightness: brightness);
      await expectLater(
        find.byType(ProjectOverviewPage),
        matchesGoldenFile('goldens/overview_${brightness.name}.png'),
      );
    });
  }

  testWidgets('the quiet overview, light', (tester) async {
    await OverviewHarness(releases: [liveRelease]).pump(tester);
    await expectLater(
      find.byType(ProjectOverviewPage),
      matchesGoldenFile('goldens/overview_quiet.png'),
    );
  });
}

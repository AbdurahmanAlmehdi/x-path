@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_desktop/job/view/job_page.dart';

import '../helpers/job_fixtures.dart';
import '../helpers/load_fonts.dart';
import 'job_harness.dart';

void main() {
  setUpAll(() async {
    registerJobFallbacks();
    await loadAppFonts();
  });

  for (final brightness in Brightness.values) {
    testWidgets('the job view, ${brightness.name}', (tester) async {
      await JobHarness().pump(tester, brightness: brightness);
      await expectLater(
        find.byType(JobPage),
        matchesGoldenFile('goldens/job_view_${brightness.name}.png'),
      );
    });
  }

  testWidgets('the failed job view, light', (tester) async {
    await JobHarness(run: failedRun(), log: failedLog).pump(tester);
    await expectLater(
      find.byType(JobPage),
      matchesGoldenFile('goldens/job_view_failed.png'),
    );
  });

  testWidgets('the interrupted job view, dark', (tester) async {
    await JobHarness(run: interruptedRun())
        .pump(tester, brightness: Brightness.dark);
    await expectLater(
      find.byType(JobPage),
      matchesGoldenFile('goldens/job_view_interrupted_dark.png'),
    );
  });
}

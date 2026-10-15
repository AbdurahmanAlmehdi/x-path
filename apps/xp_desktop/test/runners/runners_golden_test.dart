@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xp_desktop/runners/runners.dart';

import '../helpers/engine_fixtures.dart';
import '../helpers/load_fonts.dart';
import '../helpers/pump_app.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('the runners view', (tester) async {
    await tester.pumpApp(
      const RunnersPage(),
      runners: runnersIn(
        RunnersState(
          loaded: true,
          runners: [busyRunner, idleRunner, lostRunner, revokedRunner],
        ),
      ),
    );
    await expectLater(
      find.byType(RunnersPage),
      matchesGoldenFile('goldens/runners_light.png'),
    );
  });
}

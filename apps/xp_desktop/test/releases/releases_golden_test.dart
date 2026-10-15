@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/releases/view/releases_page.dart';

import '../helpers/approval_fixtures.dart';
import '../helpers/load_fonts.dart';
import '../helpers/release_fixtures.dart';
import 'releases_harness.dart';

void main() {
  setUpAll(loadAppFonts);

  for (final brightness in Brightness.values) {
    testWidgets('the releases board, ${brightness.name}', (tester) async {
      await ReleasesHarness().pump(
        tester,
        brightness: brightness,
        pending: [pendingApproval],
      );
      await expectLater(
        find.byType(ReleasesPage),
        matchesGoldenFile('goldens/releases_${brightness.name}.png'),
      );
    });
  }

  testWidgets('the releases board, App Store rejected', (tester) async {
    await ReleasesHarness(
      releases: [
        reviewRelease(
          state: ReleaseState.rejected,
          stores: [
            lane(
              ReleaseStore.apple,
              StoreState.rejected,
              detail: 'REJECTED',
              changedAt: oct12(21, 14),
            ),
            lane(
              ReleaseStore.play,
              StoreState.inReview,
              changedAt: oct12(19, 40),
            ),
          ],
        ),
        liveRelease,
      ],
    ).pump(tester);
    await expectLater(
      find.byType(ReleasesPage),
      matchesGoldenFile('goldens/releases_rejected.png'),
    );
  });

  testWidgets('the releases board, no App Store Connect key', (tester) async {
    await ReleasesHarness(
      credentials: const [playAccount],
      releases: [
        reviewRelease(
          stores: [
            lane(
              ReleaseStore.apple,
              StoreState.uploaded,
              source: StatusSource.lookup,
              detail: 'On sale: 5.3.7',
              changedAt: oct12(18, 52),
            ),
            lane(
              ReleaseStore.play,
              StoreState.inReview,
              changedAt: oct12(19, 40),
            ),
          ],
        ),
        liveRelease,
      ],
    ).pump(tester);
    await expectLater(
      find.byType(ReleasesPage),
      matchesGoldenFile('goldens/releases_no_key.png'),
    );
  });

  testWidgets('the releases board, both stores live', (tester) async {
    await ReleasesHarness(
      releases: [
        reviewRelease(
          state: ReleaseState.live,
          mergeEnabled: true,
          stores: [
            lane(
              ReleaseStore.apple,
              StoreState.live,
              changedAt: DateTime.utc(2026, 10, 14, 6, 40),
            ),
            lane(
              ReleaseStore.play,
              StoreState.live,
              changedAt: DateTime.utc(2026, 10, 13, 9, 5),
            ),
          ],
        ),
        liveRelease,
      ],
    ).pump(tester);
    await expectLater(
      find.byType(ReleasesPage),
      matchesGoldenFile('goldens/releases_both_live.png'),
    );
  });
}

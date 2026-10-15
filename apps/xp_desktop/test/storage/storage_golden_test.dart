@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:xp_desktop/projects/bloc/projects_bloc.dart';
import 'package:xp_desktop/storage/storage.dart';

import '../helpers/engine_fixtures.dart';
import '../helpers/fakes.dart';
import '../helpers/load_fonts.dart';
import '../helpers/pump_app.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('the storage view', (tester) async {
    await tester.pumpApp(
      const StoragePage(),
      storage: storageIn(StorageState(loaded: true, report: storageReport)),
      projects: projectsIn(
        const ProjectsState(loaded: true, projects: [mataa]),
      ),
    );
    await expectLater(
      find.byType(StoragePage),
      matchesGoldenFile('goldens/storage_light.png'),
    );
  });
}

@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_desktop/projects/bloc/projects_bloc.dart';
import 'package:xp_desktop/shell/shell.dart';

import '../helpers/fakes.dart';
import '../helpers/load_fonts.dart';
import '../helpers/pump_app.dart';

void main() {
  setUpAll(loadAppFonts);

  for (final brightness in Brightness.values) {
    testWidgets('the shell, ${brightness.name}', (tester) async {
      final repository = MockProjectsRepository();
      when(() => repository.watchCredentials(any()))
          .thenAnswer((_) => const Stream.empty());
      await tester.pumpApp(
        const AppShell(),
        brightness: brightness,
        projectsRepository: repository,
        projects: projectsIn(
          const ProjectsState(loaded: true, projects: [mataa, captain]),
        ),
      );
      // The brand image decodes on the real event loop.
      final brand = tester.element(find.byType(Image));
      await tester.runAsync(
        () => precacheImage(
          const AssetImage('assets/brand/xpath-sidebar.png'),
          brand,
        ),
      );
      await tester.pump();
      await expectLater(
        find.byType(AppShell),
        matchesGoldenFile('goldens/app_shell_${brightness.name}.png'),
      );
    });
  }
}

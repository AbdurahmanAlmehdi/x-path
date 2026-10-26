import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_desktop/projects/bloc/projects_bloc.dart';
import 'package:xp_desktop/shell/shell.dart';

import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';

/// Every page of the shell meets the contrast and tap-target guidelines in
/// both themes (U6c).
void main() {
  const pages = <ShellDestination>[
    HomeDestination(),
    ProjectDestination('prj_1'),
    ReleasesDestination('prj_1'),
    RunsDestination('prj_1'),
    TestsDestination('prj_1'),
    JobDestination('run_1', projectId: 'prj_1'),
    ApprovalsDestination(),
    RunnersDestination(),
    StorageDestination(),
    CredentialsDestination(),
    EnginesDestination(),
    SettingsDestination(),
    AddProjectDestination(),
  ];

  for (final brightness in Brightness.values) {
    for (final page in pages) {
      testWidgets('$page meets the guidelines, ${brightness.name}', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        final projects = quietProjects();
        when(projects.watchProjects).thenAnswer((_) => const Stream.empty());
        await tester.pumpApp(
          const AppShell(),
          brightness: brightness,
          shell: ShellCubit(page),
          projectsRepository: projects,
          projects: projectsIn(
            const ProjectsState(loaded: true, projects: [mataa, captain]),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        await expectLater(tester, meetsGuideline(textContrastGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        handle.dispose();
      });
    }
  }
}

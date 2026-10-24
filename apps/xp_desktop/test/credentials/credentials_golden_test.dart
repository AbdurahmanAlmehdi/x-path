@Tags(['golden'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_desktop/credentials/credentials.dart';
import 'package:xp_desktop/projects/bloc/projects_bloc.dart';
import 'package:xp_desktop/widgets/widgets.dart';
import 'package:xp_repositories/xp_repositories.dart';

import '../helpers/fakes.dart';
import '../helpers/load_fonts.dart';
import '../helpers/pump_app.dart';

void main() {
  setUpAll(loadAppFonts);

  late MockCredentialsRepository credentials;
  late MockProjectsRepository projects;

  setUp(() {
    credentials = MockCredentialsRepository();
    projects = MockProjectsRepository();
    when(credentials.watchCredentials).thenAnswer(
      (_) => Stream.value(Snapshot([teamKey, playAccountKey, slackWebhook])),
    );
    when(() => projects.watchCredentials('prj_1'))
        .thenAnswer((_) => Stream.value(Snapshot([ascKey, devAscKey])));
  });

  for (final brightness in Brightness.values) {
    testWidgets('the credentials page, ${brightness.name}', (tester) async {
      await tester.pumpApp(
        const CredentialsPage(),
        brightness: brightness,
        credentialsRepository: credentials,
        projectsRepository: projects,
        projects: projectsIn(
          const ProjectsState(loaded: true, projects: [mataa, captain]),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(CredentialsPage),
        matchesGoldenFile('goldens/credentials_${brightness.name}.png'),
      );
    });
  }

  testWidgets('the credentials of a flavor, with the picker open', (
    tester,
  ) async {
    await tester.pumpApp(
      Builder(
        builder: (context) => XpButton(
          label: 'Open',
          onPressed: () => showFlavorCredentialsSheet(
            context,
            project: mataa,
            target: (app: '.', appName: 'Mataa customer app', flavor: 'dev'),
          ),
        ),
      ),
      credentialsRepository: credentials,
      projectsRepository: projects,
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('flavorCredentials.asc_key')),
        matching: find.text('Change…'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Every flavor of Mataa customer app'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Dialog),
      matchesGoldenFile('goldens/flavor_credentials_sheet.png'),
    );
  });
}

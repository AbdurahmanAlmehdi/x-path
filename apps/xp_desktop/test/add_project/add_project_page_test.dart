import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_desktop/add_project/add_project.dart';
import 'package:xp_desktop/shell/cubit/shell_cubit.dart';
import 'package:xp_repositories/xp_repositories.dart';

import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';

void main() {
  late MockProjectsRepository projects;
  late ShellCubit shell;

  setUp(() {
    projects = MockProjectsRepository();
    shell = ShellCubit(const AddProjectDestination());
    when(() => projects.addProject('/src/app')).thenAnswer((_) async => mataa);
    when(() => projects.scanProject('prj_1')).thenAnswer((_) async => mataa);
    when(() => projects.removeProject('prj_1')).thenAnswer((_) async {});
  });

  Future<void> pump(
    WidgetTester tester, {
    EngineStatus status = EngineStatus.connected,
    bool local = true,
    Future<String?> Function()? pickFolder,
  }) => tester.pumpApp(
    const AddProjectPage(),
    shell: shell,
    projectsRepository: projects,
    services: testServices(pickFolder: pickFolder),
    connection: connectionIn(
      connectedTo(status: status, active: local ? localEngine : macMini),
    ),
  );

  final folder = find.byKey(const Key('addProject.folder'));

  group('AddProjectPage', () {
    testWidgets('picks a folder, adds it and reviews the scan', (tester) async {
      await pump(tester, pickFolder: () async => '/src/app');
      await tester.tap(find.text('Add and scan'));
      verifyNever(() => projects.addProject(any()));

      await tester.tap(find.text('Choose folder…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add and scan'));
      await tester.pumpAndSettle();
      expect(
        find.text('Review the scan of acme/mataa_new_app'),
        findsOneWidget,
      );
      expect(find.text('Mataa customer app'), findsOneWidget);

      await tester.tap(find.text('Scan again'));
      await tester.pumpAndSettle();
      verify(() => projects.scanProject('prj_1')).called(1);

      await tester.tap(find.text('Done'));
      expect(shell.state, const ProjectDestination('prj_1'));
    });

    testWidgets('a cancelled pick changes nothing', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Choose folder…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add and scan'));
      verifyNever(() => projects.addProject(any()));
    });

    testWidgets('removes the project it added', (tester) async {
      await pump(tester);
      await tester.enterText(folder, '/src/app');
      await tester.pump();
      await tester.tap(find.text('Add and scan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove project'));
      await tester.pumpAndSettle();
      expect(shell.state, const HomeDestination());
    });

    testWidgets('says why the engine refused the folder', (tester) async {
      when(
        () => projects.addProject(any()),
      ).thenThrow(const ApiException('Not a git repository.', statusCode: 422));
      await pump(tester);
      await tester.enterText(folder, '/tmp');
      await tester.pump();
      await tester.tap(find.text('Add and scan'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'The engine could not add this folder: Not a git repository.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows what failed during the review', (tester) async {
      when(() => projects.scanProject(any()))
          .thenThrow(const ConnectionException('Connection refused.'));
      await pump(tester);
      await tester.enterText(folder, '/src/app');
      await tester.pump();
      await tester.tap(find.text('Add and scan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scan again'));
      await tester.pumpAndSettle();
      expect(find.text('Connection refused.'), findsOneWidget);
    });

    testWidgets('on a remote engine the folder is typed, not picked', (
      tester,
    ) async {
      await pump(tester, local: false);
      expect(find.text('Choose folder…'), findsNothing);
      expect(
        find.text(
          'The folder has to be on mac-mini, the machine the engine runs on.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('is read-only while the engine is away', (tester) async {
      await pump(tester, status: EngineStatus.unreachable);
      await tester.enterText(folder, '/src/app');
      await tester.pump();
      await tester.tap(find.text('Add and scan'));
      verifyNever(() => projects.addProject(any()));
    });
  });
}

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_desktop/add_project/add_project.dart';
import 'package:xp_desktop/settings/settings.dart';
import 'package:xp_desktop/shell/cubit/shell_cubit.dart';
import 'package:xp_desktop/widgets/widgets.dart';
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
    SettingsRepository? settings,
  }) => tester.pumpApp(
    const AddProjectPage(),
    shell: shell,
    projectsRepository: projects,
    settingsRepository: settings,
    services: testServices(pickFolder: pickFolder),
    connection: connectionIn(
      connectedTo(status: status, active: local ? localEngine : macMini),
    ),
  );

  final folder = find.byKey(const Key('addProject.folder'));

  group('AddProjectPage without a GitHub token', () {
    testWidgets('says so and connects GitHub in place, keeping the folder', (
      tester,
    ) async {
      final settings = quietSettings(
        token: const GitHubTokenStatus(stored: false),
      );
      await pump(tester, settings: settings);
      await tester.pumpAndSettle();

      expect(
        find.textContaining('so it cannot add a project from GitHub'),
        findsOneWidget,
      );
      await tester.enterText(folder, '/src/app');
      await tester.pump();
      expect(
        find.descendant(
          of: find.byKey(const Key('addProject.github')),
          matching: find.byType(GitHubTokenSection),
        ),
        findsOneWidget,
      );
      expect(shell.state, const AddProjectDestination());
      expect(
        tester
            .widget<EditableText>(
              find.descendant(of: folder, matching: find.byType(EditableText)),
            )
            .controller
            .text,
        '/src/app',
      );
    });

    testWidgets('says when GitHub refuses the token', (tester) async {
      await pump(
        tester,
        settings: quietSettings(
          token: const GitHubTokenStatus(
            stored: true,
            status: CredentialStatus.rejected,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining("GitHub refused the engine's token"),
        findsOneWidget,
      );
    });

    testWidgets('asks for the token again when adding fails', (tester) async {
      final settings = quietSettings();
      when(() => projects.addProject(any())).thenThrow(
        const ApiException(
          'There is no GitHub token.',
          statusCode: 502,
          code: ApiErrorCode.upstreamError,
        ),
      );
      await pump(tester, settings: settings);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('addProject.github')), findsNothing);
      when(settings.gitHubToken)
          .thenAnswer((_) async => const GitHubTokenStatus(stored: false));

      await tester.enterText(folder, '/src/app');
      await tester.pump();
      await tester.tap(find.text('Add and scan'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('addProject.github')), findsOneWidget);
      verify(settings.gitHubToken).called(2);
    });
  });

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
      expect(find.text('Remove acme/mataa_new_app?'), findsOneWidget);
      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();
      verifyNever(() => projects.removeProject(any()));
      expect(shell.state, const AddProjectDestination());

      await tester.tap(find.text('Remove project'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byKey(confirmDialogKey),
          matching: find.text('Remove project'),
        ),
      );
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

    testWidgets('offers the SSH URL of an HTTPS origin and uses it', (
      tester,
    ) async {
      const sshUrl = 'git@bitbucket.org:ws/mobile/shop_app.git';
      when(() => projects.addProject('/src/shop')).thenThrow(
        const SshUrlRequired(
          'XPath has no credentials for bitbucket.org over HTTPS; use the SSH '
          'URL $sshUrl.',
          sshUrl: sshUrl,
        ),
      );
      when(() => projects.addProject('/src/shop', sshUrl: sshUrl))
          .thenAnswer((_) async => shop);
      await pump(tester);
      await tester.enterText(folder, '/src/shop');
      await tester.pump();
      await tester.tap(find.text('Add and scan'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Add the folder from $sshUrl instead?'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('addProject.useSsh')));
      await tester.pumpAndSettle();

      verify(() => projects.addProject('/src/shop', sshUrl: sshUrl)).called(1);
      expect(
        find.text('Review the scan of ws/mobile/shop_app'),
        findsOneWidget,
      );
    });

    testWidgets('says the GitHub token is for GitHub projects only', (
      tester,
    ) async {
      await pump(
        tester,
        settings: quietSettings(token: const GitHubTokenStatus(stored: false)),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('a project on another git host needs none'),
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

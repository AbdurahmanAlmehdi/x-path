import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/add_project/view/add_project_page.dart';
import 'package:xp_desktop/app/app.dart';
import 'package:xp_desktop/approvals/approvals.dart';
import 'package:xp_desktop/credentials/view/credentials_page.dart';
import 'package:xp_desktop/engines/view/engines_page.dart';
import 'package:xp_desktop/job/view/job_page.dart';
import 'package:xp_desktop/onboarding/view/onboarding_page.dart';
import 'package:xp_desktop/project_overview/view/project_overview_page.dart';
import 'package:xp_desktop/projects/bloc/projects_bloc.dart';
import 'package:xp_desktop/projects/view/no_projects_page.dart';
import 'package:xp_desktop/releases/view/releases_page.dart';
import 'package:xp_desktop/runners/runners.dart';
import 'package:xp_desktop/settings/settings.dart';
import 'package:xp_desktop/shell/shell.dart';
import 'package:xp_desktop/storage/storage.dart';
import 'package:xp_desktop/tests/tests.dart';
import 'package:xp_desktop/widgets/widgets.dart';
import 'package:xp_desktop/workflow_builder/workflow_builder.dart';
import 'package:xp_macos_services/testing.dart';
import 'package:xp_repositories/xp_repositories.dart';

import '../helpers/approval_fixtures.dart';
import '../helpers/engine_fixtures.dart';
import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';
import '../workflow_builder/workflow_builder_harness.dart';

void main() {
  setUpAll(() {
    registerFallbackValue(const EngineCheckRequested());
  });

  late MockProjectsRepository repository;

  setUp(() {
    repository = MockProjectsRepository();
    when(() => repository.watchCredentials(any()))
        .thenAnswer((_) => const Stream.empty());
  });

  Future<void> pumpShell(
    WidgetTester tester, {
    ShellCubit? shell,
    ProjectsState projects = const ProjectsState(
      loaded: true,
      projects: [mataa, captain],
    ),
    EngineConnectionBloc? connection,
  }) => tester.pumpApp(
    const AppShell(),
    shell: shell,
    projects: projectsIn(projects),
    connection: connection,
    projectsRepository: repository,
  );

  group('AppShell', () {
    testWidgets('XPath ▸ Settings… shows the settings', (tester) async {
      final shell = ShellCubit();
      final menu = FakeAppMenu();
      await tester.pumpApp(
        const AppShell(),
        shell: shell,
        projects: projectsIn(
          const ProjectsState(loaded: true, projects: [mataa]),
        ),
        projectsRepository: repository,
        services: testServices(appMenu: menu),
      );

      menu.chooseSettings();
      await tester.pump();

      expect(shell.state, const SettingsDestination());
      await tester.pumpWidget(const SizedBox());
      menu.chooseSettings();
    });

    testWidgets('shows the first project at home', (tester) async {
      await pumpShell(tester);
      expect(find.byType(ProjectOverviewPage), findsOneWidget);
      expect(find.text('main · 1 app'), findsOneWidget);
    });

    testWidgets('shows nothing before the projects load', (tester) async {
      await pumpShell(tester, projects: const ProjectsState());
      expect(find.byType(ProjectOverviewPage), findsNothing);
      expect(find.byType(NoProjectsPage), findsNothing);
    });

    testWidgets('shows the empty state without projects', (tester) async {
      final shell = ShellCubit();
      await pumpShell(
        tester,
        shell: shell,
        projects: const ProjectsState(loaded: true),
      );
      expect(find.byType(NoProjectsPage), findsOneWidget);
      expect(find.text('No projects yet'), findsNWidgets(2));
      await tester.tap(find.text('Add project…').last);
      await tester.pump();
      expect(shell.state, const AddProjectDestination());
    });

    for (final (destination, page) in [
      (const ProjectDestination('prj_2'), ProjectOverviewPage),
      (const JobDestination('run_1'), JobPage),
      (const AddProjectDestination(), AddProjectPage),
      (const ReleasesDestination('prj_1'), ReleasesPage),
      (const TestsDestination('prj_1'), TestsPage),
      (const RunnersDestination(), RunnersPage),
      (const StorageDestination(), StoragePage),
      (const ApprovalsDestination(), ApprovalsPage),
      (const CredentialsDestination('prj_1'), CredentialsPage),
      (const EnginesDestination(), EnginesPage),
      (const OnboardingDestination(), OnboardingPage),
      (const SettingsDestination(github: true), SettingsPage),
    ]) {
      testWidgets('shows $page for $destination', (tester) async {
        await pumpShell(tester, shell: ShellCubit(destination));
        expect(find.byType(page), findsOneWidget);
      });
    }
  });

  testWidgets('AppShell shows the workflow builder of a project', (
    tester,
  ) async {
    await tester.pumpApp(
      const AppShell(),
      shell: ShellCubit(const WorkflowsDestination('prj_1')),
      projects: projectsIn(
        const ProjectsState(loaded: true, projects: [mataa, captain]),
      ),
      projectsRepository: repository,
      workflowsRepository: workflowsRepository(),
    );
    await settle(tester);
    expect(find.byType(WorkflowBuilderPage), findsOneWidget);
    expect(const WorkflowsDestination('prj_1', workflowId: 'wf_1').props, [
      'prj_1',
      'wf_1',
    ]);
  });

  group('Sidebar', () {
    testWidgets('shows the rows of the selected project and the approvals', (
      tester,
    ) async {
      final shell = ShellCubit(const ProjectDestination('prj_1'));
      await tester.pumpApp(
        const Sidebar(),
        shell: shell,
        projects: projectsIn(
          const ProjectsState(loaded: true, projects: [mataa, captain]),
        ),
        pendingApprovals: pendingIn(
          PendingApprovalsState(
            loaded: true,
            approvals: [pendingApproval, mergeApproval],
          ),
        ),
      );
      expect(find.text('1 app · 1 needs you'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      await tester.tap(find.text('Releases'));
      await tester.pump();
      expect(shell.state, const ReleasesDestination('prj_1'));
      await tester.tap(find.text('Tests'));
      await tester.pump();
      expect(shell.state, const TestsDestination('prj_1'));
      expect(shell.projectId, 'prj_1');
      await tester.tap(find.text('Workflows'));
      await tester.pump();
      expect(shell.state, const WorkflowsDestination('prj_1'));
      expect(shell.projectId, 'prj_1');
      await tester.tap(find.text('Overview'));
      await tester.pump();
      expect(shell.state, const ProjectDestination('prj_1'));
      await tester.tap(find.text('Approvals'));
      await tester.pump();
      expect(shell.state, const ApprovalsDestination());
      expect(find.text('Releases'), findsNothing);
    });

    testWidgets('says how many runners are busy and what storage frees', (
      tester,
    ) async {
      final shell = ShellCubit();
      await tester.pumpApp(
        const Sidebar(),
        shell: shell,
        projects: projectsIn(
          const ProjectsState(loaded: true, projects: [mataa]),
        ),
        runners: runnersIn(
          RunnersState(loaded: true, runners: [busyRunner, idleRunner]),
        ),
        storage: storageIn(StorageState(loaded: true, report: storageReport)),
      );
      expect(find.text('1 busy'), findsOneWidget);
      expect(
        find.text('${formatSize(storageReport.reclaimableBytes)} free-able'),
        findsOneWidget,
      );
      await tester.tap(find.text('Runners'));
      await tester.pump();
      expect(shell.state, const RunnersDestination());
      await tester.tap(find.text('Storage'));
      await tester.pump();
      expect(shell.state, const StorageDestination());
    });

    testWidgets('lists the projects with what their scan found', (
      tester,
    ) async {
      await pumpShell(tester);
      expect(
        find.descendant(
          of: find.byType(Sidebar),
          matching: find.text('mataa_new_app'),
        ),
        findsOneWidget,
      );
      expect(find.text('1 app · 1 warning'), findsOneWidget);
      expect(find.text('mataa_captain'), findsOneWidget);
      expect(find.text('2 apps · 1 error'), findsOneWidget);
    });

    testWidgets('a project without findings shows its apps only', (
      tester,
    ) async {
      await pumpShell(
        tester,
        projects: const ProjectsState(
          loaded: true,
          projects: [
            Project(
              id: 'prj_3',
              githubRepoId: 3,
              fullName: 'acme/guest',
              remote: 'r',
              defaultBaseBranch: 'main',
            ),
          ],
        ),
      );
      expect(find.text('0 apps'), findsOneWidget);
    });

    testWidgets('says when the engine has no project', (tester) async {
      await pumpShell(tester, projects: const ProjectsState(loaded: true));
      expect(find.text('No projects yet'), findsWidgets);
    });

    testWidgets('navigates', (tester) async {
      final shell = ShellCubit();
      await pumpShell(tester, shell: shell);
      await tester.tap(find.text('mataa_captain'));
      await tester.pump();
      expect(shell.state, const ProjectDestination('prj_2'));
      await tester.tap(find.text('Credentials'));
      await tester.pump();
      expect(shell.state, const CredentialsDestination());
      await tester.tap(find.text('Engines'));
      await tester.pump();
      expect(shell.state, const EnginesDestination());
      await tester.tap(find.text('Settings'));
      await tester.pump();
      expect(shell.state, const SettingsDestination());
      await tester.tap(find.text('Add project…'));
      await tester.pump();
      expect(shell.state, const AddProjectDestination());
    });

    testWidgets('highlights a row under the mouse', (tester) async {
      await pumpShell(tester);
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.text('Credentials')));
      await tester.pump();
      await gesture.moveTo(tester.getCenter(find.text('mataa_captain')));
      await tester.pump();
      await gesture.moveTo(Offset.zero);
      await tester.pump();
    });
  });

  group('EngineSwitcher', () {
    testWidgets('switches engines and opens the engine list', (tester) async {
      final connection = connectionIn(connectedTo());
      final shell = ShellCubit();
      await pumpShell(tester, connection: connection, shell: shell);
      expect(find.text('This Mac'), findsOneWidget);
      expect(find.text('connected'), findsOneWidget);

      await tester.tap(find.text('This Mac'));
      await tester.pumpAndSettle();
      expect(find.text('mac-mini:7480'), findsOneWidget);
      await tester.tap(find.text('mac-mini'));
      await tester.pumpAndSettle();
      verify(() => connection.add(EngineSelected(macMini.id))).called(1);

      await tester.tap(find.text('This Mac'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Manage engines…'));
      await tester.pumpAndSettle();
      expect(shell.state, const EnginesDestination());
    });
  });

  group('ConnectionBanner', () {
    for (final (status, text) in [
      (EngineStatus.reconnecting, 'This Mac stopped answering'),
      (EngineStatus.unreachable, 'This Mac is unreachable'),
      (EngineStatus.secretsLocked, 'The Keychain on This Mac is locked'),
      (EngineStatus.rejected, 'This Mac refused the token'),
    ]) {
      testWidgets('says the engine is ${status.name}', (tester) async {
        final connection = connectionIn(connectedTo(status: status));
        final shell = ShellCubit();
        await tester.pumpApp(
          const ConnectionBanner(),
          connection: connection,
          shell: shell,
        );
        expect(find.textContaining(text), findsOneWidget);
        if (status == EngineStatus.rejected) {
          expect(find.text('Retry'), findsNothing);
        } else {
          await tester.tap(find.text('Retry'));
          verify(() => connection.add(const EngineCheckRequested())).called(1);
        }
        await tester.tap(find.text('Engines…'));
        expect(shell.state, const EnginesDestination());
      });
    }

    testWidgets('is hidden while connected or connecting', (tester) async {
      for (final status in [EngineStatus.connected, EngineStatus.connecting]) {
        await tester.pumpApp(
          const ConnectionBanner(),
          connection: connectionIn(connectedTo(status: status)),
        );
        expect(find.text('Retry'), findsNothing);
      }
    });

    testWidgets('follows the status as it changes', (tester) async {
      final connection = MockEngineConnectionBloc();
      whenListen(
        connection,
        Stream.fromIterable([
          connectedTo(status: EngineStatus.reconnecting),
          connectedTo(),
        ]),
        initialState: connectedTo(),
      );
      await tester.pumpApp(const ConnectionBanner(), connection: connection);
      await tester.pump();
      expect(find.text('Retry'), findsNothing);
    });
  });
}

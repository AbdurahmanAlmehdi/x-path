import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/add_project/view/add_project_page.dart';
import 'package:xp_desktop/app/app.dart';
import 'package:xp_desktop/approvals/approvals.dart';
import 'package:xp_desktop/credentials/view/credentials_page.dart';
import 'package:xp_desktop/dispatch/dispatch.dart';
import 'package:xp_desktop/engines/view/engines_page.dart';
import 'package:xp_desktop/job/view/job_page.dart';
import 'package:xp_desktop/local_engine/local_engine.dart';
import 'package:xp_desktop/onboarding/view/onboarding_page.dart';
import 'package:xp_desktop/project_overview/view/project_overview_page.dart';
import 'package:xp_desktop/projects/bloc/projects_bloc.dart';
import 'package:xp_desktop/projects/view/no_projects_page.dart';
import 'package:xp_desktop/releases/view/releases_page.dart';
import 'package:xp_desktop/runners/runners.dart';
import 'package:xp_desktop/runs/view/runs_page.dart';
import 'package:xp_desktop/settings/settings.dart';
import 'package:xp_desktop/shell/shell.dart';
import 'package:xp_desktop/storage/storage.dart';
import 'package:xp_desktop/tests/tests.dart';
import 'package:xp_desktop/widgets/widgets.dart';
import 'package:xp_desktop/workflow_builder/workflow_builder.dart';
import 'package:xp_macos_services/testing.dart';
import 'package:xp_repositories/xp_repositories.dart';

import '../dispatch/dispatch_harness.dart';
import '../helpers/approval_fixtures.dart';
import '../helpers/engine_fixtures.dart';
import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';
import '../workflow_builder/workflow_builder_harness.dart';

void main() {
  setUpAll(() {
    registerFallbackValue(const EngineCheckRequested());
    registerDispatchFallbacks();
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

    testWidgets('⌘N dispatches for the shown project from any of its pages', (
      tester,
    ) async {
      await tester.pumpApp(
        const AppShell(),
        shell: ShellCubit(const ReleasesDestination('prj_1')),
        projects: projectsIn(
          const ProjectsState(loaded: true, projects: [mataa, captain]),
        ),
        projectsRepository: repository,
        workflowsRepository: DispatchHarness().workflows,
      );
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(find.byType(DispatchSheet), findsOneWidget);
    });

    testWidgets('⌘N does nothing without a project', (tester) async {
      await tester.pumpApp(
        const AppShell(),
        shell: ShellCubit(const RunnersDestination()),
        projects: projectsIn(
          const ProjectsState(loaded: true, projects: [mataa]),
        ),
        projectsRepository: repository,
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(find.byType(DispatchSheet), findsNothing);
    });

    testWidgets('⌘1–⌘9 show the projects in sidebar order', (tester) async {
      final shell = ShellCubit(const RunnersDestination());
      await tester.pumpApp(
        const AppShell(),
        shell: shell,
        projects: projectsIn(
          const ProjectsState(loaded: true, projects: [mataa, captain]),
        ),
        projectsRepository: repository,
      );
      Future<void> press(LogicalKeyboardKey key) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(key);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pump();
      }

      await press(LogicalKeyboardKey.digit2);
      expect(shell.state, ProjectDestination(captain.id));
      await press(LogicalKeyboardKey.digit9);
      expect(shell.state, ProjectDestination(captain.id));
      await press(LogicalKeyboardKey.digit1);
      expect(shell.state, ProjectDestination(mataa.id));
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
      (const RunsDestination('prj_1'), RunsPage),
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

  group('ShellCubit', () {
    blocTest<ShellCubit, ShellDestination>(
      'shows a destination at once without a guard',
      build: ShellCubit.new,
      act: (shell) => shell.show(const RunnersDestination()),
      expect: () => [const RunnersDestination()],
    );

    blocTest<ShellCubit, ShellDestination>(
      'stays when the guard keeps the destination',
      build: ShellCubit.new,
      act: (shell) async {
        shell
          ..guard(() async => false)
          ..show(const RunnersDestination());
        await Future<void>.delayed(Duration.zero);
      },
      expect: () => const <ShellDestination>[],
    );

    blocTest<ShellCubit, ShellDestination>(
      'leaves once the guard lets go, and asks nothing for the shown one',
      build: ShellCubit.new,
      act: (shell) async {
        var asked = 0;
        shell
          ..guard(() async {
            asked++;
            return true;
          })
          ..show(const HomeDestination())
          ..show(const RunnersDestination());
        await Future<void>.delayed(Duration.zero);
        expect(asked, 1);
      },
      expect: () => [const RunnersDestination()],
    );

    blocTest<ShellCubit, ShellDestination>(
      'asks nothing once the guard is released, and keeps a newer guard',
      build: ShellCubit.new,
      act: (shell) async {
        final release = shell.guard(() async => false);
        shell.guard(() async => false);
        release();
        shell.show(const RunnersDestination());
        await Future<void>.delayed(Duration.zero);
        shell.guard(() async => true)();
        shell.show(const StorageDestination());
      },
      expect: () => [const StorageDestination()],
    );

    test('does not leave once closed', () async {
      final answer = Completer<bool>();
      final shell = ShellCubit()
        ..guard(() => answer.future)
        ..show(const RunnersDestination());
      await shell.close();
      answer.complete(true);
      await Future<void>.delayed(Duration.zero);
      expect(shell.state, const HomeDestination());
    });
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
      (EngineStatus.reconnecting, 'mac-mini stopped answering'),
      (EngineStatus.unreachable, 'mac-mini is unreachable'),
      (EngineStatus.secretsLocked, 'The Keychain on mac-mini is locked'),
      (EngineStatus.rejected, 'mac-mini refused the token'),
    ]) {
      testWidgets('says the engine is ${status.name}', (tester) async {
        final connection = connectionIn(
          connectedTo(status: status, active: macMini),
        );
        final shell = ShellCubit();
        await tester.pumpApp(
          const ConnectionBanner(),
          connection: connection,
          shell: shell,
        );
        expect(find.textContaining(text), findsOneWidget);
        expect(find.text('Set up this Mac again'), findsNothing);
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

    testWidgets('says how to unlock a locked Keychain', (tester) async {
      await tester.pumpApp(
        const ConnectionBanner(),
        connection: connectionIn(
          connectedTo(status: EngineStatus.secretsLocked, active: macMini),
        ),
      );
      expect(
        find.textContaining('unlock its login keychain in Keychain Access'),
        findsOneWidget,
      );
    });

    testWidgets('sets this Mac up again when its engine refuses the token', (
      tester,
    ) async {
      final shell = ShellCubit();
      await tester.pumpApp(
        const ConnectionBanner(),
        connection: connectionIn(connectedTo(status: EngineStatus.rejected)),
        shell: shell,
      );
      await tester.tap(find.text('Set up this Mac again'));
      expect(shell.state, const OnboardingDestination());
    });

    testWidgets('is hidden while connected or connecting', (tester) async {
      for (final status in [EngineStatus.connected, EngineStatus.connecting]) {
        await tester.pumpApp(
          const ConnectionBanner(),
          connection: connectionIn(connectedTo(status: status)),
        );
        expect(find.text('Retry'), findsNothing);
      }
    });

    group('for the engine on this Mac', () {
      final unreachable = connectedTo(status: EngineStatus.unreachable);

      testWidgets('says it is not running and starts it', (tester) async {
        final local = localEngineIn(const LocalEngineState(running: false));
        final shell = ShellCubit();
        await tester.pumpApp(
          const ConnectionBanner(),
          connection: connectionIn(unreachable),
          localEngine: local,
          shell: shell,
        );
        expect(
          find.text("The engine on this Mac isn't running."),
          findsOneWidget,
        );
        expect(find.text('Retry'), findsNothing);
        expect(find.text('Open Login Items…'), findsNothing);
        await tester.tap(find.text('Start engine'));
        verify(
          () => local.add(
            const LocalEngineStartRequested(tokenName: 'XPath app on MacBook'),
          ),
        ).called(1);
        await tester.tap(find.text('Engines…'));
        expect(shell.state, const EnginesDestination());
      });

      testWidgets('shows the start in progress', (tester) async {
        await tester.pumpApp(
          const ConnectionBanner(),
          connection: connectionIn(unreachable),
          localEngine: localEngineIn(
            const LocalEngineState(progress: LocalEngineProgress.starting),
          ),
        );
        expect(find.text('Starting the engine on this Mac…'), findsOneWidget);
        final button = tester.widget<XpButton>(
          find.byKey(const Key('banner.startEngine')),
        );
        expect(button.busy, isTrue);
        expect(button.onPressed, isNull);
      });

      for (final (failure, message, text) in [
        (LocalEngineFailure.noEngine, null, 'This copy of XPath has no engine'),
        (LocalEngineFailure.unsupported, null, 'needs macOS 13'),
        (
          LocalEngineFailure.refused,
          'Operation not permitted',
          'macOS did not start the engine: Operation not permitted',
        ),
        (LocalEngineFailure.timedOut, null, 'within 30 seconds'),
        (
          LocalEngineFailure.token,
          'locked',
          'could not make a new token for this app: locked',
        ),
      ]) {
        testWidgets('says why it did not start: ${failure.name}', (
          tester,
        ) async {
          await tester.pumpApp(
            const ConnectionBanner(),
            connection: connectionIn(unreachable),
            localEngine: localEngineIn(
              LocalEngineState(
                running: false,
                progress: LocalEngineProgress.failed,
                failure: failure,
                message: message,
              ),
            ),
          );
          expect(find.textContaining(text), findsOneWidget);
          expect(find.text('Start engine'), findsOneWidget);
        });
      }

      testWidgets('shows the log when the engine did not answer', (
        tester,
      ) async {
        final revealed = <String>[];
        await tester.pumpApp(
          const ConnectionBanner(),
          connection: connectionIn(unreachable),
          services: testServices(
            revealFile: (path) async => revealed.add(path),
          ),
          localEngine: localEngineIn(
            const LocalEngineState(
              running: false,
              progress: LocalEngineProgress.failed,
              failure: LocalEngineFailure.timedOut,
            ),
          ),
        );
        await tester.tap(find.text('Show log in Finder'));
        expect(revealed, [
          '/Users/me/Library/Application Support/XPath/service-logs/xpd.log',
        ]);
      });

      testWidgets('opens Login Items when macOS waits for the owner', (
        tester,
      ) async {
        final local = localEngineIn(
          const LocalEngineState(
            running: false,
            progress: LocalEngineProgress.failed,
            failure: LocalEngineFailure.needsApproval,
          ),
        );
        await tester.pumpApp(
          const ConnectionBanner(),
          connection: connectionIn(unreachable),
          localEngine: local,
        );
        expect(find.textContaining('Login Items, then start'), findsOneWidget);
        await tester.tap(find.text('Open Login Items…'));
        verify(() => local.add(const LocalEngineLoginItemsRequested()))
            .called(1);
      });
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

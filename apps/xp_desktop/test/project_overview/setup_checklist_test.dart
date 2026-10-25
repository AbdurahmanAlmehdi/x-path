import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/app/app.dart';
import 'package:xp_desktop/credentials/credentials.dart';
import 'package:xp_desktop/project_overview/project_overview.dart';
import 'package:xp_desktop/projects/view/no_projects_page.dart';
import 'package:xp_desktop/shell/cubit/shell_cubit.dart';
import 'package:xp_desktop/widgets/widgets.dart';
import 'package:xp_repositories/xp_repositories.dart';

import '../dispatch/dispatch_harness.dart';
import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';

class _MockSetupChecklistBloc
    extends MockBloc<SetupChecklistEvent, SetupChecklistState>
    implements SetupChecklistBloc;

void main() {
  Future<void> pumpView(
    WidgetTester tester,
    SetupChecklistState state, {
    ShellCubit? shell,
    AppServices? services,
    ProjectsRepository? projectsRepository,
    WorkflowsRepository? workflowsRepository,
    EngineConnectionBloc? connection,
  }) async {
    final bloc = _MockSetupChecklistBloc();
    whenListen(
      bloc,
      const Stream<SetupChecklistState>.empty(),
      initialState: state,
    );
    await tester.pumpApp(
      BlocProvider<SetupChecklistBloc>.value(
        value: bloc,
        child: const SingleChildScrollView(child: SetupChecklistView()),
      ),
      shell: shell,
      services: services,
      projectsRepository: projectsRepository,
      workflowsRepository: workflowsRepository,
      connection: connection,
    );
  }

  testWidgets('NoProjects shows the checklist and adds a project', (
    tester,
  ) async {
    final shell = ShellCubit();
    await tester.pumpApp(const NoProjectsPage(), shell: shell);
    await tester.pumpAndSettle();

    expect(find.text('Get to a first build'), findsOneWidget);
    expect(find.text('2 of 6 done'), findsOneWidget);
    await tester.tap(find.text('Add…'));
    expect(shell.state, const AddProjectDestination());
  });

  testWidgets('connects GitHub from Settings', (tester) async {
    final shell = ShellCubit();
    await pumpView(
      tester,
      const SetupChecklistState(loaded: true),
      shell: shell,
    );

    expect(find.text('Connect GitHub'), findsOneWidget);
    await tester.tap(find.text('Connect…'));
    expect(shell.state, const SettingsDestination(github: true));
  });

  testWidgets('opens the credentials and the store ids of the flavor', (
    tester,
  ) async {
    final projects = MockProjectsRepository();
    when(() => projects.watchCredentials(any()))
        .thenAnswer((_) => Stream.value(const Snapshot([])));
    await pumpView(
      tester,
      const SetupChecklistState(
        loaded: true,
        project: mataa,
        hasRelease: false,
        gitHubConnected: true,
      ),
      projectsRepository: projects,
    );

    expect(
      find.text(
        'Every flavor needs the keys that sign and upload it. prod has none '
        'yet.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Assign…'));
    await tester.pumpAndSettle();
    expect(find.text('Credentials of prod'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Set ids…'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('flavorCredentials.storeIds')), findsOneWidget);
  });

  testWidgets('says why no runner can build and links the guide', (
    tester,
  ) async {
    final shell = ShellCubit();
    final opened = <Uri>[];
    await pumpView(
      tester,
      const SetupChecklistState(
        loaded: true,
        project: mataa,
        hasRelease: false,
        waitReasons: ['No connected runner can do ios-sign.'],
      ),
      shell: shell,
      services: testServices(openUrl: (url) async => opened.add(url)),
    );

    expect(find.text('No connected runner can do ios-sign.'), findsOneWidget);
    await tester.tap(find.text('Runners guide'));
    expect(opened, [guideUri('runners.md')]);
    await tester.tap(find.text('Runners'));
    expect(shell.state, const RunnersDestination());
  });

  testWidgets('tries an unsigned build of a project with Android', (
    tester,
  ) async {
    final dispatch = DispatchHarness();
    await pumpView(
      tester,
      const SetupChecklistState(
        loaded: true,
        project: mataa,
        hasRelease: false,
        smokeWorkflowId: 'wf_smoke',
      ),
      workflowsRepository: dispatch.workflows,
    );

    await tester.tap(find.text('Try an unsigned build'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Dispatch…'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
  });

  testWidgets('offers no unsigned build to a project without Android', (
    tester,
  ) async {
    await pumpView(
      tester,
      const SetupChecklistState(
        loaded: true,
        project: Project(
          id: 'prj_9',
          host: 'github.com',
          sourceKey: '9',
          githubRepoId: 9,
          fullName: 'acme/ios_only',
          remote: 'git@github.com:acme/ios_only.git',
          defaultBaseBranch: 'main',
          profile: ProjectProfile(
            apps: [AppProfile(name: 'ios', path: '.', hasIos: true)],
          ),
        ),
        hasRelease: false,
        smokeWorkflowId: 'wf_smoke',
      ),
    );

    expect(find.text('Try an unsigned build'), findsNothing);
    expect(find.text('Dispatch…'), findsOneWidget);
  });

  testWidgets('cannot dispatch while the engine is away', (tester) async {
    await pumpView(
      tester,
      const SetupChecklistState(
        loaded: true,
        project: mataa,
        hasRelease: false,
        smokeWorkflowId: 'wf_smoke',
      ),
      connection: connectionIn(connectedTo(status: EngineStatus.unreachable)),
    );

    for (final label in ['Try an unsigned build', 'Dispatch…']) {
      final button = tester.widget<XpButton>(
        find.widgetWithText(XpButton, label),
      );
      expect(button.onPressed, isNull, reason: label);
    }
  });

  testWidgets('shows nothing once hidden', (tester) async {
    await pumpView(tester, const SetupChecklistState());

    expect(find.text('Get to a first build'), findsNothing);
    expect(find.byType(FlavorCredentialsSheet), findsNothing);
  });
}

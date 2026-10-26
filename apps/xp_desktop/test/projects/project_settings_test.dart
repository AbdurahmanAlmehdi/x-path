import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_desktop/credentials/credentials.dart';
import 'package:xp_desktop/projects/projects.dart';
import 'package:xp_desktop/shell/cubit/shell_cubit.dart';
import 'package:xp_desktop/theme/theme.dart';
import 'package:xp_desktop/widgets/widgets.dart';

import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';

void main() {
  late MockProjectsRepository projects;
  late MockApprovalsRepository approvals;
  const gates = ProjectGates({'prod_release': true, 'push': true});

  setUpAll(() {
    registerFallbackValue(const ProfileEdits());
    registerFallbackValue(const ProjectGates({}));
  });

  setUp(() {
    projects = quietProjects();
    approvals = quietApprovals();
    when(() => approvals.getGates('prj_1')).thenAnswer((_) async => gates);
    when(() => projects.editProject(any(), any()))
        .thenAnswer((_) async => mataa);
    when(() => approvals.setGates('prj_1', any())).thenAnswer(
      (invocation) async => invocation.positionalArguments[1] as ProjectGates,
    );
    when(() => projects.removeProject('prj_1')).thenAnswer((_) async {});
  });

  ProjectSettingsBloc build() =>
      ProjectSettingsBloc(projects: projects, approvals: approvals);

  group('ProjectSettingsBloc', () {
    test('events compare by value', () {
      expect(const ProjectSettingsStarted('p').props, ['p']);
      expect(const ProjectBaseBranchSaved('main').props, ['main']);
      expect(const ProjectGateChanged('push', on: false).props, [
        'push',
        false,
      ]);
      expect(const ProjectRemoveRequested().props, isEmpty);
    });

    blocTest<ProjectSettingsBloc, ProjectSettingsState>(
      'reads the gates, saves the base branch, turns a gate off, removes',
      build: build,
      act: (bloc) async {
        bloc.add(const ProjectSettingsStarted('prj_1'));
        await Future<void>.delayed(Duration.zero);
        bloc.add(const ProjectBaseBranchSaved(' develop '));
        await Future<void>.delayed(Duration.zero);
        bloc.add(const ProjectGateChanged('push', on: false));
        await Future<void>.delayed(Duration.zero);
        bloc.add(const ProjectRemoveRequested());
      },
      expect: () => const [
        ProjectSettingsState(
          projectId: 'prj_1',
          command: ProjectSettingsCommand.loading,
        ),
        ProjectSettingsState(
          projectId: 'prj_1',
          gates: {'prod_release': true, 'push': true},
        ),
        ProjectSettingsState(
          projectId: 'prj_1',
          command: ProjectSettingsCommand.saving,
          gates: {'prod_release': true, 'push': true},
        ),
        ProjectSettingsState(
          projectId: 'prj_1',
          gates: {'prod_release': true, 'push': true},
          saved: 1,
        ),
        ProjectSettingsState(
          projectId: 'prj_1',
          command: ProjectSettingsCommand.saving,
          gates: {'prod_release': true, 'push': true},
          saved: 1,
        ),
        ProjectSettingsState(
          projectId: 'prj_1',
          gates: {'prod_release': true, 'push': false},
          saved: 1,
        ),
        ProjectSettingsState(
          projectId: 'prj_1',
          command: ProjectSettingsCommand.removing,
          gates: {'prod_release': true, 'push': false},
          saved: 1,
        ),
        ProjectSettingsState(
          projectId: 'prj_1',
          gates: {'prod_release': true, 'push': false},
          saved: 1,
          removed: true,
        ),
      ],
      verify: (_) => verify(
        () => projects.editProject(
          'prj_1',
          const ProfileEdits(defaultBaseBranch: 'develop'),
        ),
      ).called(1),
    );

    blocTest<ProjectSettingsBloc, ProjectSettingsState>(
      'says what the engine refused',
      setUp: () =>
          when(() => approvals.getGates('prj_1'))
              .thenThrow(const ConnectionException('away')),
      build: build,
      act: (bloc) => bloc.add(const ProjectSettingsStarted('prj_1')),
      skip: 1,
      expect: () => const [
        ProjectSettingsState(projectId: 'prj_1', error: 'away'),
      ],
      verify: (bloc) => expect(bloc.state.busy, isFalse),
    );
  });

  group('ProjectSettingsPage', () {
    Future<void> pump(WidgetTester tester, {ShellCubit? shell}) async {
      await tester.pumpApp(
        const ProjectSettingsPage('prj_1'),
        shell: shell,
        projectsRepository: projects,
        approvalsRepository: approvals,
        projects: projectsIn(
          const ProjectsState(loaded: true, projects: [mataa]),
        ),
      );
      tester.view.physicalSize = const Size(1440, 1600);
      await tester.pumpAndSettle();
    }

    testWidgets('shows the host, saves the branch and turns a gate off', (
      tester,
    ) async {
      await pump(tester);

      expect(find.text('acme/mataa_new_app'), findsOneWidget);
      expect(find.text(mataa.remote), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('project.baseBranch')),
        'dev',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Releases are based on dev now'), findsOneWidget);

      await tester.tap(find.text('push'));
      await tester.pumpAndSettle();
      verify(
        () => approvals.setGates(
          'prj_1',
          const ProjectGates({'prod_release': true, 'push': false}),
        ),
      ).called(1);
    });

    testWidgets('opens the store ids of a flavor', (tester) async {
      await pump(tester);

      await tester.tap(find.text('Set ids…').first);
      await tester.pumpAndSettle();
      expect(find.byType(FlavorCredentialsSheet), findsOneWidget);
    });

    testWidgets('removes the project after a confirmation, then goes home', (
      tester,
    ) async {
      final shell = ShellCubit(const ProjectSettingsDestination('prj_1'));
      await pump(tester, shell: shell);

      await tester.tap(find.byKey(const Key('project.remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();
      verifyNever(() => projects.removeProject(any()));

      await tester.tap(find.byKey(const Key('project.remove')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      verify(() => projects.removeProject('prj_1')).called(1);
      expect(shell.state, const HomeDestination());
    });

    testWidgets('says when the project is gone', (tester) async {
      await tester.pumpApp(
        const ProjectSettingsPage('prj_9'),
        projects: projectsIn(const ProjectsState(loaded: true)),
      );
      expect(find.text('This project is no longer on the engine.'), findsOne);
    });
  });

  testWidgets('XpPickList filters by every word and picks', (tester) async {
    final picked = <String>[];
    await tester.pumpApp(
      XpPickList<String>(
        items: const ['5.4.1 prod', '5.3.7 prod', '5.4.1 dev'],
        selected: '5.3.7 prod',
        titleOf: (item) => item.split(' ').first,
        subtitleOf: (item) => item.split(' ').last,
        statusOf: (_) => XpStatus.releaseLive,
        searchHint: 'Find',
        onSelected: picked.add,
      ),
    );

    await tester.enterText(find.byType(XpTextField), '5.4 DEV');
    await tester.pump();
    expect(find.text('prod'), findsNothing);
    await tester.tap(find.text('dev'));
    expect(picked, ['5.4.1 dev']);
  });
}

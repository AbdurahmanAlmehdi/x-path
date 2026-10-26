import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_desktop/approvals/approvals.dart';
import 'package:xp_desktop/job/widgets/cancel_run_dialog.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/projects/bloc/projects_bloc.dart';
import 'package:xp_desktop/shell/shell.dart';
import 'package:xp_repositories/xp_repositories.dart';

import '../dispatch/dispatch_harness.dart';
import '../helpers/approval_fixtures.dart';
import '../helpers/fakes.dart';
import '../helpers/job_fixtures.dart';
import '../helpers/pump_app.dart';
import '../helpers/release_fixtures.dart';

final _devBuild = WorkflowSummary(
  id: 'wf_dev',
  projectId: 'prj_1',
  name: 'dev-build',
  builtin: true,
  version: prodWorkflow.version,
  title: 'Dev build',
);

final _archived = WorkflowSummary(
  id: 'wf_old',
  projectId: 'prj_1',
  name: 'old',
  builtin: false,
  version: prodWorkflow.version,
  archivedAt: at,
);

Run _run(String id, RunState state) {
  final run = runningRun().run;
  return Run(
    id: id,
    projectId: run.projectId,
    workflowId: 'wf_dev',
    workflowVersionId: run.workflowVersionId,
    sha: run.sha,
    state: state,
    locksProject: false,
    version: '1.2.3+4',
    createdAt: run.createdAt,
    jobs: const [],
  );
}

void main() {
  late MockProjectsRepository projects;
  late MockReleasesRepository releases;
  late MockJobsRepository jobs;
  late MockWorkflowsRepository workflows;
  late MockApprovalsRepository approvals;

  final running = _run('run_2', RunState.running);
  final failed = _run('run_1', RunState.failed);

  setUpAll(registerDispatchFallbacks);

  setUp(() {
    projects = MockProjectsRepository();
    releases = MockReleasesRepository();
    jobs = quietJobs();
    workflows = MockWorkflowsRepository();
    approvals = MockApprovalsRepository();
    when(projects.watchProjects)
        .thenAnswer((_) => Stream.value(const Snapshot([mataa, captain])));
    when(() => projects.watchCredentials(any()))
        .thenAnswer((_) => const Stream.empty());
    when(releases.watchReleases)
        .thenAnswer((_) => Stream.value(Snapshot([liveRelease])));
    when(() => releases.watchReleases(projectId: any(named: 'projectId')))
        .thenAnswer((_) => Stream.value(Snapshot([liveRelease])));
    when(() => jobs.watchRuns('prj_1', limit: CommandPaletteBloc.limit))
        .thenAnswer(
          (_) => Stream.value(Snapshot(RunsResponse([running, failed]))),
        );
    when(() => workflows.listWorkflows('prj_1'))
        .thenAnswer((_) async => [_devBuild, _archived]);
    when(
      () => workflows.plan(any(), any(), any()),
    ).thenAnswer((_) async => const DispatchPlan(flavors: [], platforms: []));
    when(() => approvals.watchApprovals(state: ApprovalState.pending))
        .thenAnswer((_) => Stream.value(Snapshot([pendingApproval])));
  });

  CommandPaletteBloc build() => CommandPaletteBloc(
    projects: projects,
    releases: releases,
    jobs: jobs,
    workflows: workflows,
    approvals: approvals,
  );

  group('CommandPaletteBloc', () {
    test('events and entries compare by value', () {
      expect(const CommandPaletteOpened(projectId: 'p').props, ['p']);
      expect(const CommandPaletteQueryChanged('q').props, ['q']);
      expect(CommandPaletteRunAgainRequested(failed).props, [failed]);
      expect(CommandPaletteCancelRequested(failed).props, [failed]);
      expect(const GoToProject(mataa).props, [mataa]);
      expect(GoToRelease(liveRelease).props, [liveRelease]);
      expect(GoToRun(failed, workflow: 'w').props, [failed, 'w']);
      expect(GoToWorkflow(_devBuild).props, [_devBuild]);
      expect(const GoToPage(RunnersDestination()).props, [
        const RunnersDestination(),
      ]);
      expect(const DispatchEntry(mataa).props, [mataa]);
      expect(RunAgainEntry(failed).props, [failed, null]);
      expect(CancelEntry(running).props, [running, null]);
      expect(ApproveEntry(pendingApproval).props, [pendingApproval]);
      expect(const DispatchEntry(mataa).destination, isNull);
      expect(
        const GoToProject(mataa).destination,
        const ProjectDestination('prj_1'),
      );
      expect(
        GoToRelease(liveRelease).destination,
        const ReleasesDestination('prj_1', releaseId: 'rel_1'),
      );
      expect(
        GoToRun(failed).destination,
        JobDestination('run_1', projectId: failed.projectId),
      );
      expect(
        GoToWorkflow(_devBuild).destination,
        const WorkflowsDestination('prj_1', workflowId: 'wf_dev'),
      );
    });

    blocTest<CommandPaletteBloc, CommandPaletteState>(
      'lists the commands, then the places, of the shown project',
      build: build,
      act: (bloc) => bloc.add(const CommandPaletteOpened(projectId: 'prj_1')),
      expect: () => [
        const CommandPaletteState(loading: true),
        CommandPaletteState(
          entries: [
            const DispatchEntry(mataa),
            ApproveEntry(pendingApproval),
            CancelEntry(running, workflow: 'Dev build'),
            RunAgainEntry(failed, workflow: 'Dev build'),
            const GoToProject(mataa),
            const GoToProject(captain),
            const GoToPage(ReleasesDestination('prj_1')),
            const GoToPage(RunsDestination('prj_1')),
            const GoToPage(TestsDestination('prj_1')),
            const GoToPage(WorkflowsDestination('prj_1')),
            GoToRun(running, workflow: 'Dev build'),
            GoToRun(failed, workflow: 'Dev build'),
            GoToWorkflow(_devBuild),
            GoToRelease(liveRelease),
            const GoToPage(ApprovalsDestination()),
            const GoToPage(RunnersDestination()),
            const GoToPage(CredentialsDestination('prj_1')),
            const GoToPage(StorageDestination()),
            const GoToPage(EnginesDestination()),
            const GoToPage(SettingsDestination()),
          ],
        ),
      ],
    );

    blocTest<CommandPaletteBloc, CommandPaletteState>(
      'without a project, and with what cannot be read left out',
      setUp: () {
        when(projects.watchProjects)
            .thenAnswer((_) => Stream.error(const ConnectionException('x')));
        when(releases.watchReleases).thenAnswer((_) => const Stream.empty());
      },
      build: build,
      act: (bloc) => bloc.add(const CommandPaletteOpened()),
      skip: 1,
      expect: () => [
        CommandPaletteState(
          entries: [
            ApproveEntry(pendingApproval),
            const GoToPage(ApprovalsDestination()),
            const GoToPage(RunnersDestination()),
            const GoToPage(CredentialsDestination()),
            const GoToPage(StorageDestination()),
            const GoToPage(EnginesDestination()),
            const GoToPage(SettingsDestination()),
          ],
        ),
      ],
      verify: (_) => verifyNever(() => workflows.listWorkflows(any())),
    );

    blocTest<CommandPaletteBloc, CommandPaletteState>(
      'keeps the query, and matches every word of it, in any order',
      build: build,
      act: (bloc) => bloc.add(const CommandPaletteQueryChanged('run DEV')),
      expect: () => [const CommandPaletteState(query: 'run DEV')],
      verify: (bloc) {
        final state = bloc.state.copyWith(
          entries: [
            GoToRun(failed, workflow: 'Dev'),
            const GoToProject(mataa),
          ],
        );
        expect(
          state.matches(
            (entry) => entry is GoToRun ? 'Run Dev build' : 'acme/mataa',
          ),
          [GoToRun(failed, workflow: 'Dev')],
        );
      },
    );
  });

  group('the palette', () {
    late ShellCubit shell;

    Future<void> open(WidgetTester tester, {WorkflowsRepository? flows}) async {
      shell = ShellCubit(const ProjectDestination('prj_1'));
      await tester.pumpApp(
        const AppShell(),
        shell: shell,
        projectsRepository: projects,
        releasesRepository: releases,
        jobsRepository: jobs,
        workflowsRepository: flows ?? workflows,
        approvalsRepository: approvals,
        projects: projectsIn(
          const ProjectsState(loaded: true, projects: [mataa, captain]),
        ),
      );
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
    }

    testWidgets('⌘K opens it; typing filters, ↓ and ↩ go', (tester) async {
      await open(tester);

      expect(find.byType(CommandPalette), findsOneWidget);
      expect(find.text('Dispatch… acme/mataa_new_app'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(CommandPalette),
          matching: find.text('⌘N'),
        ),
        findsOneWidget,
      );

      await tester.enterText(find.byKey(const Key('palette.query')), 'go to');
      await tester.pumpAndSettle();
      expect(find.text('Dispatch… acme/mataa_new_app'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.byType(CommandPalette), findsNothing);
      expect(shell.state, const RunsDestination('prj_1'));
    });

    testWidgets('says when nothing matches', (tester) async {
      await open(tester);

      await tester.enterText(find.byKey(const Key('palette.query')), 'zzz');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(find.text('Nothing matches.'), findsOneWidget);
    });

    testWidgets('runs a run again and opens it', (tester) async {
      when(() => jobs.runAgain('run_1'))
          .thenAnswer((_) async => _run('run_3', RunState.queued));
      await open(tester);

      await tester.tap(find.text('Run again: Dev build 1.2.3+4'));
      await tester.pumpAndSettle();

      expect(shell.state, const JobDestination('run_3', projectId: 'prj_1'));
    });

    testWidgets('says why a command failed', (tester) async {
      when(() => jobs.runAgain('run_1'))
          .thenThrow(const ConnectionException('The engine is away.'));
      await open(tester);

      await tester.tap(find.text('Run again: Dev build 1.2.3+4'));
      await tester.pumpAndSettle();

      expect(find.text('The engine is away.'), findsOneWidget);
    });

    testWidgets('asks before it cancels a run', (tester) async {
      when(() => jobs.watchRunJobs('run_2'))
          .thenAnswer((_) => Stream.value(Snapshot(runningRun())));
      when(() => jobs.cancelRun('run_2')).thenAnswer((_) async => running);
      await open(tester);

      await tester.tap(find.text('Cancel: Dev build 1.2.3+4'));
      await tester.pumpAndSettle();
      expect(find.byType(CancelRunDialog), findsOneWidget);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.period);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();

      verify(() => jobs.cancelRun('run_2')).called(1);
    });

    testWidgets('reviews an approval in its sheet', (tester) async {
      when(() => approvals.watchApproval('apr_1'))
          .thenAnswer((_) => Stream.value(Snapshot(pendingApproval)));
      await open(tester);

      await tester.tap(find.text('Review: store_submission 5.4.1+3283'));
      await tester.pumpAndSettle();

      expect(find.byType(ApprovalReviewSheet), findsOneWidget);
      // The palette opens the review; only the owner decides (D-13).
      verifyNever(() => approvals.approve(any(), reason: any(named: 'reason')));
      verifyNever(() => approvals.deny(any(), reason: any(named: 'reason')));
    });

    testWidgets('dispatches for the shown project', (tester) async {
      await open(tester, flows: DispatchHarness().workflows);

      await tester.tap(find.text('Dispatch… acme/mataa_new_app'));
      await tester.pumpAndSettle();

      expect(find.text('Dispatch 4 jobs'), findsOneWidget);
    });
  });

  testWidgets('labels every entry', (tester) async {
    await tester.pumpApp(const SizedBox());
    final l10n = AppLocalizations.of(tester.element(find.byType(SizedBox)));

    expect(
      paletteLabel(l10n, GoToRelease(liveRelease)),
      'Release 5.3.7+3200 · prod',
    );
    expect(paletteLabel(l10n, GoToWorkflow(_archived)), 'Workflow old');
    expect(
      paletteLabel(
        l10n,
        GoToRun(
          Run(
            id: 'run_9',
            projectId: 'prj_1',
            workflowId: 'wf_x',
            workflowVersionId: 'wfv_x',
            sha: sha,
            state: RunState.succeeded,
            locksProject: false,
            createdAt: at,
            jobs: const [],
          ),
        ),
      ),
      'Run wf_x 9a3bc0d',
    );
    expect(
      paletteLabel(l10n, const GoToPage(SettingsDestination())),
      'Go to Settings',
    );
    expect(paletteKeys(const GoToProject(mataa)), isNull);
    for (final page in [
      const HomeDestination(),
      const ProjectDestination('p'),
      const JobDestination('r'),
      const AddProjectDestination(),
      const OnboardingDestination(),
    ]) {
      expect(pageLabel(l10n, page), isNotEmpty);
    }
  });
}

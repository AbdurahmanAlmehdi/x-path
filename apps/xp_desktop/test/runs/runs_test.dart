import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_desktop/projects/bloc/projects_bloc.dart';
import 'package:xp_desktop/runs/bloc/runs_bloc.dart';
import 'package:xp_desktop/runs/view/runs_page.dart';
import 'package:xp_desktop/runs/widgets/run_row.dart';
import 'package:xp_desktop/shell/cubit/shell_cubit.dart';
import 'package:xp_repositories/xp_repositories.dart';

import '../helpers/fakes.dart';
import '../helpers/job_fixtures.dart';
import '../helpers/pump_app.dart';

final _summary = WorkflowSummary(
  id: 'wf_prod',
  projectId: 'prj_1',
  name: 'prod-release',
  builtin: true,
  version: prodWorkflow.version,
  title: 'Prod release',
);

Run _run(String id, RunState state, {List<String>? flavors}) => Run(
  id: id,
  projectId: 'prj_1',
  workflowId: 'wf_prod',
  workflowVersionId: 'wfv_1',
  sha: 'a' * 40,
  state: state,
  locksProject: false,
  version: '5.4.1',
  build: 3283,
  createdAt: at,
  jobs: const [],
  request: flavors == null
      ? null
      : DispatchRequest(flavors: flavors, platforms: const ['ios']),
);

void main() {
  late MockJobsRepository jobs;
  late MockWorkflowsRepository workflows;
  late Map<(String?, RunState?, int), StreamController<Snapshot<RunsResponse>>>
  streams;

  setUp(() {
    jobs = MockJobsRepository();
    workflows = MockWorkflowsRepository();
    streams = {};
    when(
      () => jobs.watchRuns(
        'prj_1',
        workflowId: any(named: 'workflowId'),
        state: any(named: 'state'),
        limit: any(named: 'limit'),
      ),
    ).thenAnswer((invocation) {
      final key = (
        invocation.namedArguments[#workflowId] as String?,
        invocation.namedArguments[#state] as RunState?,
        invocation.namedArguments[#limit] as int,
      );
      return (streams[key] ??= StreamController()).stream;
    });
    when(() => workflows.listWorkflows('prj_1'))
        .thenAnswer((_) async => [_summary]);
  });

  RunsBloc build({int limit = 20}) => RunsBloc(
    jobs: jobs,
    workflows: workflows,
    projectId: 'prj_1',
    limit: limit,
  );

  test('events compare by value', () {
    RunsFilterChanged filter(RunState? state, String? workflowId) =>
        RunsFilterChanged(state: state, workflowId: workflowId);

    expect(filter(RunState.failed, 'w'), filter(RunState.failed, 'w'));
    expect(filter(RunState.failed, 'w'), isNot(filter(RunState.failed, 'x')));
    expect(filter(RunState.failed, 'w'), isNot(filter(null, 'w')));
    expect(const RunsSubscriptionRequested().props, isEmpty);
  });

  group('RunsBloc', () {
    blocTest<RunsBloc, RunsState>(
      'follows the runs, with the names of their workflows',
      build: build,
      act: (bloc) async {
        bloc.add(const RunsSubscriptionRequested());
        await Future<void>.delayed(Duration.zero);
        streams[(null, null, 20)]!.add(
          Snapshot(
            RunsResponse([_run('run_1', RunState.failed)]),
            cached: true,
          ),
        );
        await pumpEventQueue();
      },
      verify: (bloc) {
        expect(bloc.state.loaded, isTrue);
        expect(bloc.state.cached, isTrue);
        expect(bloc.state.runs.single.id, 'run_1');
        expect(bloc.state.workflowName('wf_prod'), 'Prod release');
        expect(bloc.state.workflowName('wf_x'), isNull);
      },
    );

    blocTest<RunsBloc, RunsState>(
      'follows the runs the filter asks for',
      build: build,
      act: (bloc) async {
        bloc.add(const RunsSubscriptionRequested());
        await Future<void>.delayed(Duration.zero);
        bloc.add(const RunsFilterChanged(state: RunState.failed));
        await Future<void>.delayed(Duration.zero);
        bloc.add(
          const RunsFilterChanged(
            state: RunState.failed,
            workflowId: 'wf_prod',
          ),
        );
        await Future<void>.delayed(Duration.zero);
        streams[('wf_prod', RunState.failed, 20)]!.add(
          Snapshot(RunsResponse([_run('run_2', RunState.failed)])),
        );
        await pumpEventQueue();
      },
      verify: (bloc) {
        expect(bloc.state.state, RunState.failed);
        expect(bloc.state.workflowId, 'wf_prod');
        expect(bloc.state.runs.single.id, 'run_2');
        verify(() => workflows.listWorkflows('prj_1')).called(1);
      },
    );

    blocTest<RunsBloc, RunsState>(
      'says why the runs could not be read, and gets on without names',
      setUp: () =>
          when(() => workflows.listWorkflows('prj_1'))
              .thenThrow(const ConnectionException('away')),
      build: build,
      act: (bloc) async {
        bloc.add(const RunsSubscriptionRequested());
        await Future<void>.delayed(Duration.zero);
        streams[(null, null, 20)]!.addError(const ConnectionException('down'));
        await pumpEventQueue();
      },
      verify: (bloc) {
        expect(bloc.state.error, 'down');
        expect(bloc.state.loaded, isTrue);
        expect(bloc.state.workflows, isEmpty);
      },
    );
  });

  group('RunsPage', () {
    Future<void> pump(WidgetTester tester, {ShellCubit? shell}) =>
        tester.pumpApp(
          const RunsPage(projectId: 'prj_1'),
          jobsRepository: jobs,
          workflowsRepository: workflows,
          shell: shell,
          projects: projectsIn(
            const ProjectsState(loaded: true, projects: [mataa]),
          ),
        );

    testWidgets('lists the runs and opens one', (tester) async {
      final shell = ShellCubit();
      await pump(tester, shell: shell);
      streams[(null, null, 100)]!.add(
        Snapshot(
          RunsResponse([
            _run('run_1', RunState.failed, flavors: ['prod']),
          ]),
        ),
      );
      await tester.pump();

      expect(find.text('Runs'), findsWidgets);
      expect(find.text('Prod release'), findsOneWidget);
      expect(find.text('prod · ios'), findsOneWidget);
      expect(find.text('5.4.1 (3283)'), findsOneWidget);
      expect(find.text('Failed'), findsOneWidget);

      await tester.tap(find.text('Prod release'));
      await tester.pump();
      expect(shell.state, const JobDestination('run_1', projectId: 'prj_1'));
    });

    // The bloc test follows one filter after another; under the widget
    // tester's fake clock a second restart of the runs never starts, so
    // each picker is tested on a page of its own.
    for (final (picker, pick, workflowId, state) in [
      ('All states', 'Failed', null, RunState.failed),
      ('All workflows', 'Prod release', 'wf_prod', null),
    ]) {
      testWidgets('filters with "$picker"', (tester) async {
        await pump(tester);
        streams[(null, null, 100)]!.add(const Snapshot(RunsResponse([])));
        await tester.pump();
        expect(find.text('No run matches.'), findsOneWidget);

        await tester.tap(find.text(picker));
        await tester.pumpAndSettle();
        await tester.tap(find.text(pick).last);
        await tester.pumpAndSettle();

        verify(
          () => jobs.watchRuns(
            'prj_1',
            workflowId: workflowId,
            state: state,
            limit: 100,
          ),
        ).called(1);
      });
    }

    testWidgets('says why the runs could not be read', (tester) async {
      await pump(tester);
      streams[(null, null, 100)]!.addError(const ConnectionException('down'));
      await tester.pump();

      expect(find.text('down'), findsOneWidget);
      streams.remove((null, null, 100));
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(streams.keys, contains((null, null, 100)), reason: 'read again');
    });
  });

  group('RecentRuns', () {
    testWidgets('lists the last runs and opens all of them', (tester) async {
      final shell = ShellCubit();
      await tester.pumpApp(
        const SingleChildScrollView(child: RecentRuns(projectId: 'prj_1')),
        jobsRepository: jobs,
        workflowsRepository: workflows,
        shell: shell,
      );
      expect(find.text('RECENT RUNS'), findsOneWidget);
      streams[(null, null, 5)]!.add(const Snapshot(RunsResponse([])));
      await tester.pump();
      expect(
        find.text(
          'Nothing has run yet. Dispatch a workflow to see its runs here.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('All runs'));
      await tester.pump();
      expect(shell.state, const RunsDestination('prj_1'));
    });
  });

  testWidgets('a right click on a run opens it or copies its commit', (
    tester,
  ) async {
    final shell = ShellCubit();
    final run = _run('run_1', RunState.failed);
    await tester.pumpApp(
      RunRow(run: run, workflowName: 'Prod release'),
      shell: shell,
    );

    await tester.tapAt(
      tester.getCenter(find.byType(RunRow)),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    expect(find.text('Copy commit'), findsOneWidget);
    expect(find.text('Copy version'), findsOneWidget);
    await tester.tap(find.text('Open job'));
    await tester.pumpAndSettle();

    expect(shell.state, const JobDestination('run_1', projectId: 'prj_1'));
  });
}

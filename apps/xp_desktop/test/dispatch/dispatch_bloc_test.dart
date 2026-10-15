import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_desktop/dispatch/bloc/dispatch_bloc.dart';
import 'package:xp_repositories/xp_repositories.dart';

import '../helpers/fakes.dart';
import '../helpers/job_fixtures.dart';

final devBuild = WorkflowSummary(
  id: 'wf_dev',
  projectId: 'prj_1',
  name: 'Dev build',
  builtin: true,
  version: prodWorkflow.version,
);

final prodSummary = WorkflowSummary(
  id: 'wf_prod',
  projectId: 'prj_1',
  name: 'Prod release',
  builtin: true,
  version: prodWorkflow.version,
);

Workflow workflowWith(String id, String yaml) => Workflow(
  id: id,
  projectId: 'prj_1',
  name: id,
  builtin: false,
  version: prodWorkflow.version,
  versions: prodWorkflow.versions,
  yaml: yaml,
);

const bumping = '''
lock: project
stages:
  - name: build
    jobs:
      build:
        steps:
          - kind: version.bump
''';

DispatchPreview previewOf(int jobs, {List<String> flavors = const ['prod']}) =>
    DispatchPreview(
      flavors: flavors,
      platforms: const ['android', 'ios'],
      currentVersion: '5.4.1+3283',
      version: '5.4.1',
      stages: [
        if (jobs > 0)
          PreviewStage(
            name: 'build',
            jobs: [
              for (var i = 0; i < jobs; i++)
                PreviewJob(
                  name: 'job $i',
                  capabilities: const [],
                  engineOnly: true,
                ),
            ],
          ),
      ],
    );

void main() {
  late MockWorkflowsRepository workflows;

  setUpAll(() {
    registerFallbackValue(mataa);
    registerFallbackValue(prodWorkflow);
    registerFallbackValue(const DispatchRequest());
  });

  setUp(() {
    workflows = MockWorkflowsRepository();
    when(() => workflows.listWorkflows('prj_1'))
        .thenAnswer((_) async => [prodSummary, devBuild]);
    when(() => workflows.getWorkflow('prj_1', 'wf_prod'))
        .thenAnswer((_) async => workflowWith('wf_prod', bumping));
    when(() => workflows.getWorkflow('prj_1', 'wf_dev'))
        .thenAnswer((_) async => workflowWith('wf_dev', '- broken'));
    when(
      () => workflows.preview(
        project: any(named: 'project'),
        workflow: any(named: 'workflow'),
        request: any(named: 'request'),
      ),
    ).thenAnswer((_) async => previewOf(2));
  });

  DispatchBloc build() => DispatchBloc(workflows: workflows, project: mataa);

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 5));

  group('DispatchState', () {
    test('starts on the base branch and the first app', () {
      final state = build().state;
      expect(state.app, '.');
      expect(state.ref, 'main');
      expect(state.bumps, isFalse);
      expect(state.chosenFlavors, isEmpty);
      expect(state.chosenPlatforms, isEmpty);
      expect(state.canDispatch, isFalse);
      expect(state.request, const DispatchRequest(app: '.', ref: 'main'));
    });

    test('a project without an app runs at the root', () {
      const empty = Project(
        id: 'prj_9',
        githubRepoId: 9,
        fullName: 'a/b',
        remote: 'r',
        defaultBaseBranch: 'dev',
      );
      final bloc = DispatchBloc(workflows: workflows, project: empty);
      expect(bloc.state.app, '.');
      expect(bloc.state.copyWith(ref: '  ').request.ref, isNull);
    });
  });

  test('events compare by value', () {
    expect(const DispatchStarted().props, isEmpty);
    expect(const DispatchWorkflowChanged('w').props, ['w']);
    expect(const DispatchAppChanged('.').props, ['.']);
    expect(const DispatchFlavorToggled('dev').props, ['dev']);
    expect(const DispatchPlatformToggled('ios').props, ['ios']);
    expect(const DispatchRefChanged('main').props, ['main']);
    expect(const DispatchRefKindChanged(RefKind.tag).props, [RefKind.tag]);
    expect(const DispatchBumpChanged(VersionBump.patch).props, [
      VersionBump.patch,
    ]);
    expect(const DispatchSubmitted().props, isEmpty);
  });

  group('DispatchBloc', () {
    blocTest<DispatchBloc, DispatchState>(
      'loads the workflows and previews the first',
      build: build,
      act: (bloc) => bloc.add(const DispatchStarted()),
      wait: const Duration(milliseconds: 20),
      verify: (bloc) {
        final state = bloc.state;
        expect(state.status, DispatchStatus.ready);
        expect(state.workflows, [prodSummary, devBuild]);
        expect(state.workflow?.id, 'wf_prod');
        expect(state.bumps, isTrue);
        expect(state.previewing, isFalse);
        expect(state.preview, previewOf(2));
        expect(state.chosenFlavors, ['prod']);
        expect(state.chosenPlatforms, ['android', 'ios']);
        expect(state.canDispatch, isTrue);
        expect(
          state.request,
          const DispatchRequest(app: '.', ref: 'main', bump: VersionBump.keep),
        );
      },
    );

    blocTest<DispatchBloc, DispatchState>(
      'says when the project has no workflow',
      setUp: () =>
          when(() => workflows.listWorkflows('prj_1'))
              .thenAnswer((_) async => []),
      build: build,
      act: (bloc) => bloc.add(const DispatchStarted()),
      wait: const Duration(milliseconds: 20),
      verify: (bloc) {
        expect(bloc.state.status, DispatchStatus.ready);
        expect(bloc.state.workflows, isEmpty);
        expect(bloc.state.canDispatch, isFalse);
      },
    );

    blocTest<DispatchBloc, DispatchState>(
      'says why the workflows cannot be listed',
      setUp: () =>
          when(() => workflows.listWorkflows('prj_1'))
              .thenThrow(const ConnectionException('Connection refused.')),
      build: build,
      act: (bloc) => bloc.add(const DispatchStarted()),
      wait: const Duration(milliseconds: 20),
      verify: (bloc) => expect(bloc.state.error, 'Connection refused.'),
    );

    blocTest<DispatchBloc, DispatchState>(
      'changes what it previews as the sheet changes',
      build: build,
      act: (bloc) async {
        bloc.add(const DispatchStarted());
        await settle();
        bloc
          ..add(const DispatchFlavorToggled('dev'))
          ..add(const DispatchFlavorToggled('prod'))
          ..add(const DispatchPlatformToggled('ios'))
          ..add(const DispatchRefChanged('release/5.4.1'))
          ..add(const DispatchRefKindChanged(RefKind.tag))
          ..add(const DispatchBumpChanged(VersionBump.minor));
        await settle();
        bloc.add(const DispatchWorkflowChanged('wf_dev'));
        await settle();
        bloc.add(const DispatchAppChanged('.'));
      },
      wait: const Duration(milliseconds: 20),
      verify: (bloc) {
        final state = bloc.state;
        expect(state.workflow?.id, 'wf_dev');
        expect(state.outline, const WorkflowOutline());
        expect(state.bumps, isFalse);
        expect(state.flavors, isNull);
        expect(state.refKind, RefKind.tag);
        expect(
          state.request,
          const DispatchRequest(app: '.', ref: 'release/5.4.1'),
        );
        verify(
          () => workflows.preview(
            project: mataa,
            workflow: any(named: 'workflow'),
            request: const DispatchRequest(
              app: '.',
              ref: 'release/5.4.1',
              flavors: ['dev'],
              platforms: ['android'],
              bump: VersionBump.minor,
            ),
          ),
        ).called(greaterThanOrEqualTo(1));
      },
    );

    blocTest<DispatchBloc, DispatchState>(
      'says why a workflow cannot be read',
      setUp: () =>
          when(() => workflows.getWorkflow('prj_1', 'wf_dev'))
              .thenThrow(const ApiException('Gone.', statusCode: 404)),
      build: build,
      act: (bloc) => bloc.add(const DispatchWorkflowChanged('wf_dev')),
      wait: const Duration(milliseconds: 20),
      verify: (bloc) {
        expect(bloc.state.error, 'Gone.');
        expect(bloc.state.previewing, isFalse);
      },
    );

    blocTest<DispatchBloc, DispatchState>(
      'says why the preview cannot be worked out',
      setUp: () => when(
        () => workflows.preview(
          project: any(named: 'project'),
          workflow: any(named: 'workflow'),
          request: any(named: 'request'),
        ),
      ).thenThrow(const ConnectionException('down')),
      build: build,
      act: (bloc) => bloc.add(const DispatchStarted()),
      wait: const Duration(milliseconds: 20),
      verify: (bloc) {
        expect(bloc.state.error, 'down');
        expect(bloc.state.canDispatch, isFalse);
      },
    );

    blocTest<DispatchBloc, DispatchState>(
      'previews nothing before a workflow is read',
      build: build,
      act: (bloc) => bloc.add(const DispatchRefChanged('x')),
      wait: const Duration(milliseconds: 20),
      verify: (_) => verifyNever(
        () => workflows.preview(
          project: any(named: 'project'),
          workflow: any(named: 'workflow'),
          request: any(named: 'request'),
        ),
      ),
    );

    blocTest<DispatchBloc, DispatchState>(
      'dispatches the run it previews',
      setUp: () =>
          when(() => workflows.dispatch('prj_1', 'wf_prod', any()))
              .thenAnswer((_) async => runningRun().run),
      build: build,
      act: (bloc) async {
        bloc.add(const DispatchStarted());
        await settle();
        bloc.add(const DispatchSubmitted());
      },
      wait: const Duration(milliseconds: 20),
      verify: (bloc) {
        expect(bloc.state.status, DispatchStatus.dispatched);
        expect(bloc.state.run, runningRun().run);
      },
    );

    blocTest<DispatchBloc, DispatchState>(
      'says why the engine refused the dispatch',
      setUp: () =>
          when(() => workflows.dispatch('prj_1', 'wf_prod', any()))
              .thenThrow(const ApiException('Locked.', statusCode: 409)),
      build: build,
      act: (bloc) async {
        bloc.add(const DispatchStarted());
        await settle();
        bloc.add(const DispatchSubmitted());
      },
      wait: const Duration(milliseconds: 20),
      verify: (bloc) {
        expect(bloc.state.status, DispatchStatus.ready);
        expect(bloc.state.error, 'Locked.');
      },
    );

    blocTest<DispatchBloc, DispatchState>(
      'dispatches nothing that would start no job',
      setUp: () => when(
        () => workflows.preview(
          project: any(named: 'project'),
          workflow: any(named: 'workflow'),
          request: any(named: 'request'),
        ),
      ).thenAnswer((_) async => previewOf(0)),
      build: build,
      act: (bloc) async {
        bloc.add(const DispatchStarted());
        await settle();
        bloc.add(const DispatchSubmitted());
      },
      wait: const Duration(milliseconds: 20),
      verify: (_) => verifyNever(() => workflows.dispatch(any(), any(), any())),
    );
  });
}

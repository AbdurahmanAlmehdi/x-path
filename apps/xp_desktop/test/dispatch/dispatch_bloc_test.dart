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
  late MockReleasesRepository releases;

  setUpAll(() {
    registerFallbackValue(mataa);
    registerFallbackValue(prodWorkflow);
    registerFallbackValue(const DispatchRequest());
  });

  setUp(() {
    workflows = MockWorkflowsRepository();
    releases = quietReleases();
    when(() => workflows.lastInputs(any(), any()))
        .thenAnswer((_) async => const {});
    when(() => workflows.rememberInputs(any(), any(), any()))
        .thenAnswer((_) async {});
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

  DispatchBloc build() =>
      DispatchBloc(workflows: workflows, releases: releases, project: mataa);

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
      final bloc = DispatchBloc(
        workflows: workflows,
        releases: releases,
        project: empty,
      );
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
    expect(const DispatchInputChanged('a', 1).props, ['a', 1, true]);
    expect(const DispatchVersionChanged('1.2.3').props, ['1.2.3']);
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

  group('inputs', () {
    final typed = Workflow(
      id: 'wf_typed',
      projectId: 'prj_1',
      name: 'typed',
      builtin: false,
      version: prodWorkflow.version,
      versions: prodWorkflow.versions,
      yaml: bumping,
      inputs: const [
        WorkflowInput(name: 'notes', type: InputType.string),
        WorkflowInput(name: 'ids', type: InputType.json),
        WorkflowInput(name: 'release', type: InputType.release),
      ],
    );

    Release release(String version, int build, ReleaseState state, int day) =>
        Release(
          id: 'rel_$build',
          projectId: 'prj_1',
          app: '.',
          flavor: 'prod',
          version: version,
          build: build,
          state: state,
          stores: const [],
          builds: const [],
          mergeEnabled: false,
          createdAt: DateTime.utc(2026, 10, day),
          updatedAt: DateTime.utc(2026, 10, day),
        );

    setUp(() {
      when(() => workflows.getWorkflow('prj_1', 'wf_typed'))
          .thenAnswer((_) async => typed);
      when(() => workflows.lastInputs('prj_1', 'wf_typed'))
          .thenAnswer((_) async => {'notes': 'Last time', 'unknown': 1});
      when(() => releases.watchReleases(projectId: 'prj_1')).thenAnswer(
        (_) => Stream.value(
          Snapshot([
            release('5.4.0', 3200, ReleaseState.live, 1),
            release('5.4.1', 3283, ReleaseState.uploaded, 9),
            release('5.5.0', 3300, ReleaseState.building, 12),
          ]),
        ),
      );
      when(() => workflows.dispatch('prj_1', 'wf_typed', any()))
          .thenAnswer((_) async => runningRun().run);
    });

    blocTest<DispatchBloc, DispatchState>(
      'start from the last dispatch, pick the newest release, and send '
      'what is set with the version typed',
      build: build,
      act: (bloc) async {
        bloc.add(const DispatchWorkflowChanged('wf_typed'));
        await settle();
        bloc
          ..add(const DispatchInputChanged('ids', {'dev': '1'}))
          ..add(const DispatchVersionChanged(' 5.6.0 '));
        await settle();
        bloc.add(const DispatchSubmitted());
      },
      wait: const Duration(milliseconds: 20),
      verify: (bloc) {
        final state = bloc.state;
        expect(state.releases?.map((r) => r.build), [3283, 3200]);
        expect(state.noReleases, isFalse);
        const sent = DispatchRequest(
          app: '.',
          ref: 'main',
          version: '5.6.0',
          releaseVersion: '5.4.1+3283',
          inputs: {
            'notes': 'Last time',
            'ids': {'dev': '1'},
            'release': '5.4.1+3283',
          },
        );
        expect(state.request, sent);
        verify(() => workflows.dispatch('prj_1', 'wf_typed', sent)).called(1);
        verify(() => workflows.rememberInputs('prj_1', 'wf_typed', sent.inputs))
            .called(1);
      },
    );

    blocTest<DispatchBloc, DispatchState>(
      'wait for JSON that parses, and for a release to pick',
      setUp: () =>
          when(() => releases.watchReleases(projectId: 'prj_1'))
              .thenAnswer((_) => Stream.value(const Snapshot(<Release>[]))),
      build: build,
      act: (bloc) async {
        bloc.add(const DispatchWorkflowChanged('wf_typed'));
        await settle();
        bloc.add(const DispatchInputChanged('ids', null, valid: false));
      },
      wait: const Duration(milliseconds: 20),
      verify: (bloc) {
        final state = bloc.state;
        expect(state.noReleases, isTrue);
        expect(state.invalidInputs, {'ids'});
        expect(state.canDispatch, isFalse);
        expect(state.copyWith(invalidInputs: const {}).invalidInputs, isEmpty);
      },
    );

    blocTest<DispatchBloc, DispatchState>(
      'a JSON input that parses again counts again',
      build: build,
      act: (bloc) async {
        bloc.add(const DispatchWorkflowChanged('wf_typed'));
        await settle();
        bloc
          ..add(const DispatchInputChanged('ids', null, valid: false))
          ..add(const DispatchInputChanged('ids', [1]));
      },
      wait: const Duration(milliseconds: 20),
      verify: (bloc) {
        expect(bloc.state.invalidInputs, isEmpty);
        expect(bloc.state.request.inputs['ids'], [1]);
      },
    );

    test('a choice without a default sends the option it shows', () {
      final state = build().state.copyWith(
        workflow: Workflow(
          id: 'wf_choice',
          projectId: 'prj_1',
          name: 'choice',
          builtin: false,
          version: prodWorkflow.version,
          versions: prodWorkflow.versions,
          yaml: bumping,
          inputs: const [
            WorkflowInput(
              name: 'track',
              type: InputType.choice,
              options: ['internal', 'beta'],
            ),
            WorkflowInput(
              name: 'kept',
              type: InputType.choice,
              options: ['a', 'b'],
              defaultValue: 'b',
            ),
          ],
        ),
      );

      expect(state.request.inputs, {'track': 'internal'});
    });

    blocTest<DispatchBloc, DispatchState>(
      'a release that does not come is no release yet',
      setUp: () =>
          when(() => releases.watchReleases(projectId: 'prj_1'))
              .thenAnswer((_) => const Stream.empty()),
      build: build,
      act: (bloc) => bloc.add(const DispatchWorkflowChanged('wf_typed')),
      wait: const Duration(milliseconds: 20),
      verify: (bloc) => expect(bloc.state.noReleases, isTrue),
    );
  });
}

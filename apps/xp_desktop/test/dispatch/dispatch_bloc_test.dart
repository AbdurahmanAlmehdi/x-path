import 'dart:async';

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

DispatchPlan previewOf(
  int jobs, {
  List<String> flavors = const ['prod'],
  bool bumps = true,
  bool blocked = false,
}) => DispatchPlan(
  flavors: flavors,
  platforms: const ['android', 'ios'],
  currentVersion: '5.4.1+3283',
  version: bumps ? '5.4.1' : null,
  stages: [
    if (jobs > 0)
      PlannedStage(
        name: 'build',
        jobs: [
          for (var i = 0; i < jobs; i++)
            PlannedJob(name: 'job $i', engineOnly: true, local: true),
        ],
      ),
  ],
  skipped: [
    if (blocked)
      const SkippedJob(
        name: 'upload',
        stage: 'upload',
        reason: 'No credential.',
        blocks: true,
      ),
  ],
);

const _pushing = '''
stages:
  - name: finalize
    jobs:
      tag:
        steps:
          - kind: git.tag
          - kind: git.push
          - kind: github.createPr
''';

void main() {
  late MockWorkflowsRepository workflows;
  late MockReleasesRepository releases;

  group('DispatchState.gitHubStep (ADR 0015)', () {
    DispatchState stateOf(Project project, String yaml) => DispatchState(
      project: project,
      app: '.',
      ref: project.defaultBaseBranch,
      status: DispatchStatus.ready,
      workflow: workflowWith('wf', yaml),
      preview: previewOf(1),
    );

    test('names the first GitHub step for a project on another host', () {
      final state = stateOf(shop, _pushing);

      expect(state.gitHubStep, 'git.push');
      expect(state.canDispatch, isFalse);
    });

    test('catches a workflow whose only GitHub step opens a pull request', () {
      const pullRequest = '''
stages:
  - name: finalize
    jobs:
      pr:
        steps:
          - kind: git.checkout
          - kind: github.createPr
''';
      final state = stateOf(shop, pullRequest);

      expect(state.gitHubStep, 'github.createPr');
      expect(state.canDispatch, isFalse);
    });

    test('is null on GitHub, and for a workflow without GitHub steps', () {
      for (final state in [stateOf(mataa, _pushing), stateOf(shop, bumping)]) {
        expect(state.gitHubStep, isNull);
        expect(state.canDispatch, isTrue);
      }
    });
  });

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
    when(() => workflows.rememberDispatch(any(), any(), any()))
        .thenAnswer((_) async {});
    when(() => workflows.lastWorkflow(any())).thenAnswer((_) async => null);
    when(() => workflows.listWorkflows('prj_1'))
        .thenAnswer((_) async => [prodSummary, devBuild]);
    when(() => workflows.getWorkflow('prj_1', 'wf_prod'))
        .thenAnswer((_) async => workflowWith('wf_prod', bumping));
    when(() => workflows.getWorkflow('prj_1', 'wf_dev'))
        .thenAnswer((_) async => workflowWith('wf_dev', '- broken'));
    when(() => workflows.plan(any(), any(), any()))
        .thenAnswer((_) async => previewOf(2));
  });

  DispatchBloc build({Duration typingPause = Duration.zero}) => DispatchBloc(
    workflows: workflows,
    releases: releases,
    project: mataa,
    typingPause: typingPause,
  );

  /// Lets every event, and what it starts, run to its end.
  Future<void> settle() => pumpEventQueue();

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

    test('copyWith clears what it is given a null for', () {
      final state = build().state.copyWith(
        preview: () => previewOf(2),
        refNotice: () => 'Not fetched yet.',
        invalidInputs: const {'ids'},
      );
      expect(state.preview, previewOf(2));
      final cleared = state.copyWith(
        preview: () => null,
        refNotice: () => null,
        invalidInputs: const {},
      );
      expect(cleared.preview, isNull);
      expect(cleared.refNotice, isNull);
      expect(cleared.invalidInputs, isEmpty);
    });

    test('a project without an app runs at the root', () {
      const empty = Project(
        id: 'prj_9',
        host: 'github.com',
        sourceKey: '9',
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
    // Built from values, not constants, so that each pair is two objects.
    List<DispatchEvent> events(String name) => [
      DispatchStarted(workflowId: name),
      DispatchWorkflowChanged(name),
      DispatchAppChanged(name),
      DispatchFlavorToggled(name),
      DispatchPlatformToggled(name),
      DispatchRefChanged(name),
      DispatchInputChanged(name, 1),
      DispatchVersionChanged(name),
    ];
    final a = events('a');
    expect(a, events('a'));
    for (final (index, event) in a.indexed) {
      expect(event, isNot(events('b')[index]));
    }
    RefKind kind(int i) => RefKind.values[i];
    VersionBump bump(int i) => VersionBump.values[i];
    expect(DispatchRefKindChanged(kind(1)), DispatchRefKindChanged(kind(1)));
    expect(DispatchBumpChanged(bump(1)), isNot(DispatchBumpChanged(bump(2))));
    expect(const DispatchSubmitted().props, isEmpty);
  });

  group('DispatchBloc', () {
    blocTest<DispatchBloc, DispatchState>(
      'loads the workflows and previews the first',
      build: build,
      act: (bloc) async {
        bloc.add(const DispatchStarted());
        await settle();
      },
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
      'opens on the workflow asked for, by id or name, else the last one',
      setUp: () {
        when(() => workflows.listWorkflows('prj_1')).thenAnswer(
          (_) async => [
            prodSummary,
            devBuild,
            WorkflowSummary(
              id: 'wf_merge',
              projectId: 'prj_1',
              name: 'release-merge',
              builtin: true,
              version: prodWorkflow.version,
            ),
            WorkflowSummary(
              id: 'wf_old',
              projectId: 'prj_1',
              name: 'old',
              builtin: false,
              version: prodWorkflow.version,
              archivedAt: DateTime.utc(2026),
            ),
          ],
        );
        when(() => workflows.lastWorkflow('prj_1'))
            .thenAnswer((_) async => 'wf_dev');
      },
      build: build,
      act: (bloc) async {
        bloc.add(const DispatchStarted());
        await settle();
      },
      verify: (bloc) {
        expect(bloc.state.workflow?.id, 'wf_dev');
        expect(bloc.state.workflows.map((w) => w.name), [
          'Prod release',
          'Dev build',
        ]);
      },
    );

    blocTest<DispatchBloc, DispatchState>(
      'opens on a workflow named by its name',
      setUp: () => when(() => workflows.listWorkflows('prj_1')).thenAnswer(
        (_) async => [
          prodSummary,
          WorkflowSummary(
            id: 'wf_dev',
            projectId: 'prj_1',
            name: 'dev-build',
            builtin: true,
            version: prodWorkflow.version,
          ),
        ],
      ),
      build: build,
      act: (bloc) async {
        bloc.add(const DispatchStarted(workflowId: 'dev-build'));
        await settle();
      },
      verify: (bloc) => expect(bloc.state.workflow?.id, 'wf_dev'),
    );

    blocTest<DispatchBloc, DispatchState>(
      'cannot dispatch what the engine would refuse',
      setUp: () =>
          when(() => workflows.plan(any(), any(), any()))
              .thenAnswer((_) async => previewOf(2, blocked: true)),
      build: build,
      act: (bloc) async {
        bloc.add(const DispatchStarted());
        await settle();
      },
      verify: (bloc) {
        expect(bloc.state.preview?.blocked, isTrue);
        expect(bloc.state.canDispatch, isFalse);
      },
    );

    blocTest<DispatchBloc, DispatchState>(
      'says when the project has no workflow',
      setUp: () =>
          when(() => workflows.listWorkflows('prj_1'))
              .thenAnswer((_) async => []),
      build: build,
      act: (bloc) async {
        bloc.add(const DispatchStarted());
        await settle();
      },
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
      act: (bloc) async {
        bloc.add(const DispatchStarted());
        await settle();
      },
      verify: (bloc) => expect(bloc.state.error, 'Connection refused.'),
    );

    test('previews what the sheet asks for once its changes settle', () async {
      const last = DispatchRequest(
        app: '.',
        ref: 'release/5.4.1',
        flavors: ['dev'],
        platforms: ['android'],
        bump: VersionBump.minor,
      );
      when(() => workflows.plan('prj_1', 'wf_prod', last))
          .thenAnswer((_) async => previewOf(3));
      when(() => workflows.plan('prj_1', 'wf_dev', any()))
          .thenAnswer((_) async => previewOf(2, bumps: false));
      final bloc = build();
      addTearDown(bloc.close);

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

      verify(() => workflows.plan('prj_1', 'wf_prod', last)).called(1);
      expect(bloc.state.preview, previewOf(3));
      expect(bloc.state.refKind, RefKind.tag);

      bloc.add(const DispatchWorkflowChanged('wf_dev'));
      await settle();
      bloc.add(const DispatchAppChanged('.'));
      await settle();

      final state = bloc.state;
      expect(state.workflow?.id, 'wf_dev');
      expect(state.bumps, isFalse);
      expect(state.flavors, isNull);
      expect(
        state.request,
        const DispatchRequest(app: '.', ref: 'release/5.4.1'),
      );
      expect(state.preview, previewOf(2, bumps: false));
    });

    test('waits for typing to pause before it previews', () async {
      final bloc = build(typingPause: const Duration(hours: 1));
      addTearDown(bloc.close);
      bloc.add(const DispatchStarted());
      await settle();
      clearInteractions(workflows);

      bloc
        ..add(const DispatchRefChanged('r'))
        ..add(const DispatchRefChanged('re'))
        ..add(const DispatchRefChanged('rel'));
      await settle();
      verifyNever(() => workflows.plan(any(), any(), any()));
      expect(bloc.state.previewing, isTrue);
      expect(bloc.state.canDispatch, isFalse);

      // A pick is previewed at once, with what was typed.
      bloc.add(const DispatchBumpChanged(VersionBump.patch));
      await settle();
      final asked = verify(
        () => workflows.plan('prj_1', 'wf_prod', captureAny()),
      ).captured;
      expect(asked, hasLength(1));
      expect((asked.single as DispatchRequest).ref, 'rel');
    });

    test('previews what was typed once typing pauses', () async {
      final bloc = build();
      addTearDown(bloc.close);
      bloc.add(const DispatchStarted());
      await settle();

      bloc.add(const DispatchRefChanged('release/5.5.0'));
      await settle();

      verify(
        () => workflows.plan(
          'prj_1',
          'wf_prod',
          const DispatchRequest(
            app: '.',
            ref: 'release/5.5.0',
            bump: VersionBump.keep,
          ),
        ),
      ).called(1);
      expect(bloc.state.previewing, isFalse);
    });

    test(
      'drops the plan of the workflow before while the next loads',
      () async {
        final next = Completer<Workflow>();
        when(() => workflows.getWorkflow('prj_1', 'wf_dev'))
            .thenAnswer((_) => next.future);
        final bloc = build();
        addTearDown(bloc.close);
        bloc.add(const DispatchStarted());
        await settle();
        expect(bloc.state.canDispatch, isTrue);

        bloc.add(const DispatchWorkflowChanged('wf_dev'));
        await settle();

        expect(bloc.state.preview, isNull);
        expect(bloc.state.canDispatch, isFalse);
        next.complete(workflowWith('wf_dev', bumping));
        await settle();
      },
    );

    test('drops the plan the engine can no longer work out', () async {
      final bloc = build();
      addTearDown(bloc.close);
      bloc.add(const DispatchStarted());
      await settle();
      when(() => workflows.plan(any(), any(), any()))
          .thenThrow(const ConnectionException('down'));

      bloc.add(const DispatchFlavorToggled('dev'));
      await settle();

      expect(bloc.state.error, 'down');
      expect(bloc.state.preview, isNull);
      expect(bloc.state.canDispatch, isFalse);
    });

    test('dispatches a ref the engine does not have yet', () async {
      final bloc = build();
      addTearDown(bloc.close);
      bloc.add(const DispatchStarted());
      await settle();
      when(() => workflows.plan(any(), any(), any())).thenThrow(
        const ApiException(
          'This engine has no "feature/new" yet.',
          statusCode: 422,
          code: ApiErrorCode.workflowInvalid,
          hint: 'Dispatching fetches it from the repository first.',
          details: {'reason': ErrorReason.refUnknown, 'ref': 'feature/new'},
        ),
      );

      bloc.add(const DispatchRefChanged('feature/new'));
      await settle();

      expect(
        bloc.state.refNotice,
        'This engine has no "feature/new" yet. Dispatching fetches it from '
        'the repository first.',
      );
      expect(bloc.state.error, isNull);
      expect(bloc.state.preview, isNull);
      expect(bloc.state.canDispatch, isTrue);
    });

    blocTest<DispatchBloc, DispatchState>(
      'says why a workflow cannot be read',
      setUp: () =>
          when(() => workflows.getWorkflow('prj_1', 'wf_dev'))
              .thenThrow(const ApiException('Gone.', statusCode: 404)),
      build: build,
      act: (bloc) async {
        bloc.add(const DispatchWorkflowChanged('wf_dev'));
        await settle();
      },
      verify: (bloc) {
        expect(bloc.state.error, 'Gone.');
        expect(bloc.state.previewing, isFalse);
      },
    );

    blocTest<DispatchBloc, DispatchState>(
      'says why the preview cannot be worked out',
      setUp: () =>
          when(() => workflows.plan(any(), any(), any()))
              .thenThrow(const ConnectionException('down')),
      build: build,
      act: (bloc) async {
        bloc.add(const DispatchStarted());
        await settle();
      },
      verify: (bloc) {
        expect(bloc.state.error, 'down');
        expect(bloc.state.canDispatch, isFalse);
      },
    );

    blocTest<DispatchBloc, DispatchState>(
      'previews nothing before a workflow is read',
      build: build,
      act: (bloc) async {
        bloc.add(const DispatchRefChanged('x'));
        await settle();
      },
      verify: (_) => verifyNever(() => workflows.plan(any(), any(), any())),
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
        await settle();
      },
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
        await settle();
      },
      verify: (bloc) {
        expect(bloc.state.status, DispatchStatus.ready);
        expect(bloc.state.error, 'Locked.');
      },
    );

    blocTest<DispatchBloc, DispatchState>(
      'dispatches nothing that would start no job',
      setUp: () =>
          when(() => workflows.plan(any(), any(), any()))
              .thenAnswer((_) async => previewOf(0)),
      build: build,
      act: (bloc) async {
        bloc.add(const DispatchStarted());
        await settle();
        bloc.add(const DispatchSubmitted());
        await settle();
      },
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
        await settle();
      },
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
        verify(
          () => workflows.rememberDispatch('prj_1', 'wf_typed', sent.inputs),
        ).called(1);
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
        await settle();
      },
      verify: (bloc) {
        final state = bloc.state;
        expect(state.noReleases, isTrue);
        expect(state.invalidInputs, {'ids'});
        expect(state.canDispatch, isFalse);
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
        await settle();
      },
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
      act: (bloc) async {
        bloc.add(const DispatchWorkflowChanged('wf_typed'));
        await settle();
      },
      verify: (bloc) => expect(bloc.state.noReleases, isTrue),
    );
  });
}

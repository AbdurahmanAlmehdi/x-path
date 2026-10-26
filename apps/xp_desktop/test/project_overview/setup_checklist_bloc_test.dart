import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_desktop/project_overview/bloc/setup_checklist_bloc.dart';
import 'package:xp_repositories/xp_repositories.dart';

import '../helpers/fakes.dart';
import '../helpers/job_fixtures.dart';
import '../helpers/release_fixtures.dart';

WorkflowSummary _builtin(String id, String name) => WorkflowSummary(
  id: id,
  projectId: 'prj_1',
  name: name,
  builtin: true,
  version: prodWorkflow.version,
  title: name,
);

/// `mataa` whose flavors have every store id.
final _withStoreIds = Project(
  id: mataa.id,
  host: mataa.host,
  sourceKey: mataa.sourceKey,
  githubRepoId: mataa.githubRepoId,
  fullName: mataa.fullName,
  remote: mataa.remote,
  defaultBaseBranch: mataa.defaultBaseBranch,
  profile: ProjectProfile(
    apps: [
      AppProfile(
        name: 'Mataa customer app',
        path: '.',
        hasIos: true,
        hasAndroid: true,
        flavors: [
          for (final name in ['prod', 'dev'])
            FlavorProfile(
              name: name,
              entrypoint: 'lib/main_$name.dart',
              firebaseAppId: const {'android': '1:1:android:1'},
              appleAppId: '123',
            ),
        ],
      ),
    ],
  ),
);

void main() {
  late MockSettingsRepository settings;
  late MockProjectsRepository projects;
  late MockJobsRepository jobs;
  late MockReleasesRepository releases;
  late MockWorkflowsRepository workflows;

  setUpAll(() => registerFallbackValue(const DispatchRequest()));

  setUp(() {
    settings = quietSettings();
    projects = MockProjectsRepository();
    jobs = MockJobsRepository();
    releases = MockReleasesRepository();
    workflows = MockWorkflowsRepository();
    when(() => projects.watchCredentials('prj_1'))
        .thenAnswer((_) => Stream.value(Snapshot([ascKey])));
    when(() => jobs.watchRuns('prj_1', limit: 1))
        .thenAnswer((_) => Stream.value(const Snapshot(RunsResponse([]))));
    when(() => releases.watchReleases(projectId: 'prj_1'))
        .thenAnswer((_) => Stream.value(const Snapshot([])));
    when(() => workflows.listWorkflows('prj_1')).thenAnswer(
      (_) async => [
        _builtin('wf_dev', 'dev-build'),
        _builtin('wf_smoke', 'smoke-build'),
      ],
    );
    when(() => workflows.plan('prj_1', 'wf_dev', any())).thenAnswer(
      (_) async => const DispatchPlan(
        flavors: ['dev'],
        platforms: ['android', 'ios'],
        stages: [
          PlannedStage(
            name: 'build',
            jobs: [
              PlannedJob(name: 'a', engineOnly: false, local: true),
              PlannedJob(
                name: 'b',
                engineOnly: false,
                local: false,
                waitReason: 'No connected runner can do ios-sign.',
              ),
              PlannedJob(
                name: 'c',
                engineOnly: false,
                local: false,
                waitReason: 'No connected runner can do ios-sign.',
              ),
            ],
          ),
        ],
      ),
    );
  });

  SetupChecklistBloc build() => SetupChecklistBloc(
    settings: settings,
    projects: projects,
    jobs: jobs,
    releases: releases,
    workflows: workflows,
  );

  List<SetupStepKind> kinds(SetupChecklistState state) => [
    for (final step in state.steps) step.kind,
  ];

  group('SetupChecklistState', () {
    test('without a project: the engine is done, the project is next', () {
      const state = SetupChecklistState(loaded: true);

      expect(kinds(state), [
        SetupStepKind.engine,
        SetupStepKind.gitHub,
        SetupStepKind.project,
        SetupStepKind.credentials,
        SetupStepKind.storeIds,
        SetupStepKind.firstBuild,
      ]);
      expect(state.doneCount, 1);
      expect(state.visible, isTrue);
      expect(state.steps[3].target, isNull);
    });

    test('a project on another host has no GitHub step (ADR 0015)', () {
      const state = SetupChecklistState(loaded: true, project: shop);

      expect(kinds(state), isNot(contains(SetupStepKind.gitHub)));
    });

    test('names the first flavor missing credentials or store ids', () {
      final state = SetupChecklistState(
        loaded: true,
        project: mataa,
        credentials: [ascKey],
      );

      final credentials = state.steps[3];
      expect(credentials.kind, SetupStepKind.credentials);
      expect(credentials.done, isFalse);
      expect(credentials.target, (
        app: '.',
        appName: 'Mataa customer app',
        flavor: 'dev',
      ));
      expect(state.steps[4].target?.flavor, 'prod');
    });

    test('lists the runners only when a build would wait', () {
      final state = SetupChecklistState(
        loaded: true,
        project: _withStoreIds,
        waitReasons: const ['No connected runner can do android.'],
      );

      final runners = state.steps.firstWhere(
        (step) => step.kind == SetupStepKind.runners,
      );
      expect(runners.done, isFalse);
      expect(runners.reasons, ['No connected runner can do android.']);
    });

    test('hides once every step is done or a release exists', () {
      final done = SetupChecklistState(
        loaded: true,
        project: _withStoreIds,
        gitHubConnected: true,
        credentials: [
          for (final flavor in ['prod', 'dev'])
            Credential(
              id: 'crd_$flavor',
              projectId: 'prj_1',
              app: '.',
              flavor: flavor,
              kind: CredentialKind.ascKey,
              status: CredentialStatus.verified,
            ),
        ],
        hasRun: true,
        hasRelease: false,
      );
      expect(done.steps.every((step) => step.done), isTrue);
      expect(done.visible, isFalse);
      expect(
        const SetupChecklistState(
          loaded: true,
          project: mataa,
          hasRelease: true,
        ).visible,
        isFalse,
      );
      expect(const SetupChecklistState().visible, isFalse);
      expect(
        const SetupChecklistState(loaded: true, project: mataa).visible,
        isFalse,
        reason: 'the releases of the project have not arrived',
      );
    });
  });

  test('events and steps compare by value', () {
    expect(const SetupChecklistStarted(mataa).props, [mataa]);
    expect(const SetupStep(SetupStepKind.engine, done: true).props, [
      SetupStepKind.engine,
      true,
      null,
      null,
    ]);
  });

  group('SetupChecklistBloc', () {
    blocTest<SetupChecklistBloc, SetupChecklistState>(
      'without a project reads the GitHub token only',
      build: build,
      act: (bloc) => bloc.add(const SetupChecklistStarted(null)),
      expect: () => [
        const SetupChecklistState(),
        const SetupChecklistState(loaded: true, gitHubConnected: true),
      ],
      verify: (_) => verifyNever(() => workflows.listWorkflows(any())),
    );

    for (final (name, answer) in [
      ('cannot read', () async => throw const ConnectionException('down')),
      (
        'reads as refused',
        () async => const GitHubTokenStatus(
          stored: true,
          status: CredentialStatus.rejected,
        ),
      ),
    ]) {
      blocTest<SetupChecklistBloc, SetupChecklistState>(
        'GitHub is not connected when the token $name',
        setUp: () => when(settings.gitHubToken).thenAnswer((_) => answer()),
        build: build,
        act: (bloc) => bloc.add(const SetupChecklistStarted(null)),
        expect: () => [
          const SetupChecklistState(),
          const SetupChecklistState(loaded: true),
        ],
      );
    }

    blocTest<SetupChecklistBloc, SetupChecklistState>(
      'follows the credentials, runs and releases of a project, with the '
      "smoke build and the dry run's wait reasons",
      build: build,
      act: (bloc) => bloc.add(const SetupChecklistStarted(mataa)),
      expect: () => [
        const SetupChecklistState(project: mataa),
        const SetupChecklistState(
          loaded: true,
          project: mataa,
          gitHubConnected: true,
          smokeWorkflowId: 'wf_smoke',
          waitReasons: ['No connected runner can do ios-sign.'],
        ),
        isA<SetupChecklistState>().having(
          (state) => state.credentials,
          'credentials',
          [ascKey],
        ),
        isA<SetupChecklistState>()
            .having((state) => state.hasRelease, 'hasRelease', isFalse)
            .having((state) => state.visible, 'visible', isTrue),
      ],
    );

    blocTest<SetupChecklistBloc, SetupChecklistState>(
      'marks a project with a run and a release',
      setUp: () {
        when(() => jobs.watchRuns('prj_1', limit: 1)).thenAnswer(
          (_) => Stream.value(Snapshot(RunsResponse([runningRun().run]))),
        );
        when(() => releases.watchReleases(projectId: 'prj_1'))
            .thenAnswer((_) => Stream.value(Snapshot([liveRelease])));
      },
      build: build,
      act: (bloc) => bloc.add(const SetupChecklistStarted(mataa)),
      verify: (bloc) {
        expect(bloc.state.hasRun, isTrue);
        expect(bloc.state.hasRelease, isTrue);
        expect(bloc.state.visible, isFalse);
      },
    );

    blocTest<SetupChecklistBloc, SetupChecklistState>(
      'keeps the steps when the workflows or the streams cannot be read',
      setUp: () {
        when(() => workflows.listWorkflows('prj_1'))
            .thenThrow(const ConnectionException('down'));
        when(() => projects.watchCredentials('prj_1'))
            .thenAnswer((_) => Stream.error(const ConnectionException('x')));
        when(() => jobs.watchRuns('prj_1', limit: 1))
            .thenAnswer((_) => Stream.error(const ConnectionException('x')));
        when(() => releases.watchReleases(projectId: 'prj_1'))
            .thenAnswer((_) => Stream.error(const ConnectionException('x')));
      },
      build: build,
      act: (bloc) => bloc.add(const SetupChecklistStarted(mataa)),
      expect: () => [
        const SetupChecklistState(project: mataa),
        const SetupChecklistState(
          loaded: true,
          project: mataa,
          gitHubConnected: true,
        ),
      ],
    );

    blocTest<SetupChecklistBloc, SetupChecklistState>(
      'plans nothing for a project without a dev build',
      setUp: () =>
          when(() => workflows.listWorkflows('prj_1'))
              .thenAnswer((_) async => []),
      build: build,
      act: (bloc) => bloc.add(const SetupChecklistStarted(mataa)),
      verify: (bloc) {
        expect(bloc.state.smokeWorkflowId, isNull);
        expect(bloc.state.waitReasons, isEmpty);
        verifyNever(() => workflows.plan(any(), any(), any()));
      },
    );
  });
}

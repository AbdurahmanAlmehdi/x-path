import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_desktop/project_overview/bloc/project_overview_bloc.dart';
import 'package:xp_repositories/xp_repositories.dart';

import '../helpers/fakes.dart';
import '../helpers/job_fixtures.dart';
import '../helpers/release_fixtures.dart';

void main() {
  late MockReleasesRepository releases;
  late MockProjectsRepository projects;
  late MockJobsRepository jobs;
  late MockWorkflowsRepository workflows;
  late MockRunnersRepository runners;
  late StreamController<Snapshot<List<Release>>> releaseStream;

  setUpAll(() => registerFallbackValue(runningRun().run));

  setUp(() {
    releases = MockReleasesRepository();
    projects = MockProjectsRepository();
    jobs = MockJobsRepository();
    workflows = MockWorkflowsRepository();
    runners = MockRunnersRepository();
    releaseStream = StreamController<Snapshot<List<Release>>>();
    when(() => releases.watchReleases(projectId: 'prj_1'))
        .thenAnswer((_) => releaseStream.stream);
    when(() => projects.watchCredentials('prj_1'))
        .thenAnswer((_) => Stream.value(const Snapshot([verifiedKey])));
    when(runners.watchRunners)
        .thenAnswer((_) => Stream.value(Snapshot([linuxRunner])));
    when(() => jobs.watchRunJobs('run_1'))
        .thenAnswer((_) => Stream.value(Snapshot(runningRun())));
    when(() => workflows.workflowOf(any()))
        .thenAnswer((_) async => prodWorkflow);
  });

  // Never awaited: a controller nobody listened to never finishes closing.
  tearDown(() => unawaited(releaseStream.close()));

  ProjectOverviewBloc build() => ProjectOverviewBloc(
    releases: releases,
    projects: projects,
    jobs: jobs,
    workflows: workflows,
    runners: runners,
  );

  group('ProjectOverviewState', () {
    test('the hero is the newest release in flight', () {
      expect(const ProjectOverviewState().heroRelease, isNull);
      expect(
        ProjectOverviewState(releases: [buildingRelease, liveRelease])
            .heroRelease,
        buildingRelease,
      );
      expect(ProjectOverviewState(releases: [liveRelease]).heroRelease, isNull);
      expect(const ProjectOverviewState().heroStageName(0), isNull);
    });
  });

  test('events compare by value', () {
    expect(const ProjectOverviewSubscriptionRequested('p').props, ['p']);
    expect(const ProjectOverviewFilterChanged('dev').props, ['dev']);
  });

  group('ProjectOverviewBloc', () {
    blocTest<ProjectOverviewBloc, ProjectOverviewState>(
      'keeps numbered stages when the hero workflow cannot be read',
      setUp: () =>
          when(() => workflows.workflowOf(any()))
              .thenThrow(const ConnectionException('down')),
      build: build,
      act: (bloc) async {
        bloc.add(const ProjectOverviewSubscriptionRequested('prj_1'));
        await Future<void>.delayed(Duration.zero);
        releaseStream.add(Snapshot([buildingRelease]));
      },
      wait: const Duration(milliseconds: 20),
      verify: (bloc) {
        expect(bloc.state.heroRun, runningRun());
        expect(bloc.state.heroOutline, isNull);
      },
    );

    blocTest<ProjectOverviewBloc, ProjectOverviewState>(
      'follows the releases, credentials, runners and the hero run',
      build: build,
      act: (bloc) async {
        bloc.add(const ProjectOverviewSubscriptionRequested('prj_1'));
        await Future<void>.delayed(Duration.zero);
        releaseStream.add(Snapshot([buildingRelease, liveRelease]));
        await Future<void>.delayed(Duration.zero);
        releaseStream.add(Snapshot([buildingRelease, liveRelease]));
      },
      wait: const Duration(milliseconds: 20),
      verify: (bloc) {
        final state = bloc.state;
        expect(state.loaded, isTrue);
        expect(state.releases, [buildingRelease, liveRelease]);
        expect(state.credentials, [verifiedKey]);
        expect(state.runners, {linuxBuilder: 'linux-builder-01'});
        expect(state.heroRun, runningRun());
        expect(state.heroStageName(1), 'build');
        expect(state.heroStageName(9), isNull);
        verify(() => jobs.watchRunJobs('run_1')).called(1);
      },
    );

    blocTest<ProjectOverviewBloc, ProjectOverviewState>(
      'lets go of the hero run when nothing is in flight',
      build: build,
      act: (bloc) async {
        bloc.add(const ProjectOverviewSubscriptionRequested('prj_1'));
        await Future<void>.delayed(Duration.zero);
        releaseStream.add(Snapshot([buildingRelease]));
        await Future<void>.delayed(const Duration(milliseconds: 5));
        releaseStream.add(Snapshot([liveRelease]));
      },
      wait: const Duration(milliseconds: 20),
      verify: (bloc) {
        expect(bloc.state.heroRelease, isNull);
        expect(bloc.state.heroRun, isNull);
        expect(bloc.state.heroOutline, isNull);
      },
    );

    blocTest<ProjectOverviewBloc, ProjectOverviewState>(
      'gets on when the hero workflow, runners or credentials fail',
      setUp: () {
        when(() => workflows.workflowOf(any()))
            .thenThrow(const ConnectionException('down'));
        when(() => projects.watchCredentials('prj_1'))
            .thenAnswer((_) => Stream.error(const ConnectionException('x')));
        when(runners.watchRunners)
            .thenAnswer((_) => Stream.error(const ConnectionException('x')));
        when(() => jobs.watchRunJobs('run_1'))
            .thenAnswer((_) => Stream.error(const ConnectionException('x')));
      },
      build: build,
      act: (bloc) async {
        bloc.add(const ProjectOverviewSubscriptionRequested('prj_1'));
        await Future<void>.delayed(Duration.zero);
        releaseStream.add(Snapshot([buildingRelease]));
      },
      wait: const Duration(milliseconds: 20),
      verify: (bloc) {
        expect(bloc.state.heroRun, isNull);
        expect(bloc.state.credentials, isEmpty);
        expect(bloc.state.error, isNull);
      },
    );

    blocTest<ProjectOverviewBloc, ProjectOverviewState>(
      'says why the releases cannot be read, and filters the ledger',
      build: build,
      act: (bloc) async {
        bloc.add(const ProjectOverviewSubscriptionRequested('prj_1'));
        await Future<void>.delayed(Duration.zero);
        releaseStream.addError(const ApiException('Boom.', statusCode: 500));
        bloc.add(const ProjectOverviewFilterChanged('prod'));
      },
      wait: const Duration(milliseconds: 20),
      verify: (bloc) {
        expect(bloc.state.error, 'Boom.');
        expect(bloc.state.filter, 'prod');
      },
    );
  });
}

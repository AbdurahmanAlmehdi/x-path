import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_desktop/projects/bloc/projects_bloc.dart';
import 'package:xp_desktop/shell/cubit/shell_cubit.dart';
import 'package:xp_repositories/xp_repositories.dart';

import '../helpers/fakes.dart';

void main() {
  late MockProjectsRepository repository;
  late StreamController<Snapshot<List<Project>>> projects;

  setUp(() {
    repository = MockProjectsRepository();
    projects = StreamController();
    when(repository.watchProjects).thenAnswer((_) => projects.stream);
  });

  // Not awaited: a controller nobody listened to never finishes closing.
  tearDown(() => unawaited(projects.close()));

  group('ProjectsBloc', () {
    blocTest<ProjectsBloc, ProjectsState>(
      'follows the projects, cached then live, and shows an error',
      build: () => ProjectsBloc(projects: repository),
      act: (bloc) async {
        bloc.add(const ProjectsSubscriptionRequested());
        await Future<void>.delayed(Duration.zero);
        projects
          ..add(const Snapshot([mataa], cached: true))
          ..add(const Snapshot([mataa, captain]))
          ..addError(const ApiException('Gone.', statusCode: 404));
      },
      expect: () => [
        const ProjectsState(loaded: true, projects: [mataa], cached: true),
        const ProjectsState(loaded: true, projects: [mataa, captain]),
        const ProjectsState(
          loaded: true,
          projects: [mataa, captain],
          error: 'Gone.',
        ),
      ],
    );

    blocTest<ProjectsBloc, ProjectsState>(
      'scans a project again and replaces it',
      build: () => ProjectsBloc(projects: repository),
      seed: () => const ProjectsState(loaded: true, projects: [mataa, captain]),
      setUp: () =>
          when(() => repository.scanProject('prj_1'))
              .thenAnswer((_) async => _rescanned),
      act: (bloc) => bloc.add(const ProjectScanRequested('prj_1')),
      expect: () => [
        const ProjectsState(
          loaded: true,
          projects: [mataa, captain],
          scanning: 'prj_1',
        ),
        const ProjectsState(loaded: true, projects: [_rescanned, captain]),
      ],
    );

    blocTest<ProjectsBloc, ProjectsState>(
      'says why a scan failed',
      build: () => ProjectsBloc(projects: repository),
      seed: () => const ProjectsState(loaded: true, projects: [mataa]),
      setUp: () =>
          when(() => repository.scanProject('prj_1'))
              .thenThrow(const ConnectionException('Connection refused.')),
      act: (bloc) => bloc.add(const ProjectScanRequested('prj_1')),
      skip: 1,
      expect: () => [
        const ProjectsState(
          loaded: true,
          projects: [mataa],
          error: 'Connection refused.',
        ),
      ],
    );

    test('finds a project by id', () {
      const state = ProjectsState(projects: [mataa, captain]);
      expect(state.byId('prj_2'), captain);
      expect(state.byId('nope'), isNull);
      expect(state.byId(null), isNull);
      expect(const ProjectScanRequested('a').props, ['a']);
    });
  });

  group('ShellCubit', () {
    blocTest<ShellCubit, ShellDestination>(
      'shows destinations',
      build: ShellCubit.new,
      act: (cubit) => cubit
        ..show(const ProjectDestination('prj_1'))
        ..show(const CredentialsDestination('prj_1'))
        ..show(const AddProjectDestination())
        ..show(const EnginesDestination())
        ..show(const OnboardingDestination()),
      expect: () => const [
        ProjectDestination('prj_1'),
        CredentialsDestination('prj_1'),
        AddProjectDestination(),
        EnginesDestination(),
        OnboardingDestination(),
      ],
    );

    test('starts at home', () {
      expect(ShellCubit().state, const HomeDestination());
      expect(const ProjectDestination('a').props, ['a']);
      expect(const CredentialsDestination().projectId, isNull);
    });
  });
}

const _rescanned = Project(
  id: 'prj_1',
  host: 'github.com',
  sourceKey: '1',
  githubRepoId: 1,
  fullName: 'acme/mataa_new_app',
  remote: 'git@github.com:acme/mataa_new_app.git',
  defaultBaseBranch: 'main',
);

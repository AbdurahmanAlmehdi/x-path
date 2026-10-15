import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_desktop/add_project/bloc/add_project_bloc.dart';

import '../helpers/fakes.dart';

void main() {
  late MockProjectsRepository projects;

  setUp(() => projects = MockProjectsRepository());

  const refused = ApiException('Not a git repository.', statusCode: 422);

  group('AddProjectBloc', () {
    blocTest<AddProjectBloc, AddProjectState>(
      'adds the folder and shows the scan for review',
      build: () => AddProjectBloc(projects: projects),
      setUp: () =>
          when(() => projects.addProject('/src/app'))
              .thenAnswer((_) async => mataa),
      act: (bloc) => bloc.add(const AddProjectSubmitted(' /src/app ')),
      expect: () => [
        const AddProjectState(status: AddProjectStatus.adding),
        const AddProjectState(status: AddProjectStatus.review, project: mataa),
      ],
    );

    blocTest<AddProjectBloc, AddProjectState>(
      'says why the folder was refused',
      build: () => AddProjectBloc(projects: projects),
      setUp: () => when(() => projects.addProject(any())).thenThrow(refused),
      act: (bloc) => bloc.add(const AddProjectSubmitted('/tmp')),
      skip: 1,
      expect: () => [
        const AddProjectState(
          status: AddProjectStatus.failed,
          error: 'Not a git repository.',
        ),
      ],
    );

    blocTest<AddProjectBloc, AddProjectState>(
      'scans again',
      build: () => AddProjectBloc(projects: projects),
      seed: () => const AddProjectState(
        status: AddProjectStatus.review,
        project: mataa,
      ),
      setUp: () =>
          when(() => projects.scanProject('prj_1'))
              .thenAnswer((_) async => captain),
      act: (bloc) => bloc.add(const AddProjectRescanned()),
      expect: () => [
        const AddProjectState(
          status: AddProjectStatus.scanning,
          project: mataa,
        ),
        const AddProjectState(
          status: AddProjectStatus.review,
          project: captain,
        ),
      ],
    );

    blocTest<AddProjectBloc, AddProjectState>(
      'keeps the review when a scan fails',
      build: () => AddProjectBloc(projects: projects),
      seed: () => const AddProjectState(
        status: AddProjectStatus.review,
        project: mataa,
      ),
      setUp: () => when(() => projects.scanProject(any())).thenThrow(refused),
      act: (bloc) => bloc.add(const AddProjectRescanned()),
      skip: 1,
      expect: () => [
        const AddProjectState(
          status: AddProjectStatus.review,
          project: mataa,
          error: 'Not a git repository.',
        ),
      ],
    );

    blocTest<AddProjectBloc, AddProjectState>(
      'removes the project it added',
      build: () => AddProjectBloc(projects: projects),
      seed: () => const AddProjectState(
        status: AddProjectStatus.review,
        project: mataa,
      ),
      setUp: () =>
          when(() => projects.removeProject('prj_1')).thenAnswer((_) async {}),
      act: (bloc) => bloc.add(const AddProjectDiscarded()),
      expect: () => [const AddProjectState(status: AddProjectStatus.discarded)],
    );

    blocTest<AddProjectBloc, AddProjectState>(
      'keeps the review when it cannot remove the project',
      build: () => AddProjectBloc(projects: projects),
      seed: () => const AddProjectState(
        status: AddProjectStatus.review,
        project: mataa,
      ),
      setUp: () => when(() => projects.removeProject(any())).thenThrow(refused),
      act: (bloc) => bloc.add(const AddProjectDiscarded()),
      expect: () => [
        const AddProjectState(
          status: AddProjectStatus.review,
          project: mataa,
          error: 'Not a git repository.',
        ),
      ],
    );

    blocTest<AddProjectBloc, AddProjectState>(
      'does nothing to a project it has not added',
      build: () => AddProjectBloc(projects: projects),
      act: (bloc) => bloc
        ..add(const AddProjectRescanned())
        ..add(const AddProjectDiscarded()),
      expect: () => <AddProjectState>[],
    );

    test('events compare by value', () {
      expect(const AddProjectSubmitted('a').props, ['a']);
      expect(const AddProjectRescanned(), const AddProjectRescanned());
    });
  });
}

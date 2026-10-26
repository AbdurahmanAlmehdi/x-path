import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_desktop/approvals/bloc/pending_approvals_bloc.dart';
import 'package:xp_desktop/projects/bloc/projects_bloc.dart';
import 'package:xp_desktop/shell/shell.dart';
import 'package:xp_repositories/xp_repositories.dart';

import '../helpers/approval_fixtures.dart';
import '../helpers/fakes.dart';
import '../helpers/job_fixtures.dart';
import '../helpers/pump_app.dart';
import '../helpers/release_fixtures.dart';

Release _of(String projectId, Release release) =>
    Release.fromJson({...release.toJson(), 'projectId': projectId});

const _shop = Project(
  id: 'prj_3',
  host: 'bitbucket.org',
  sourceKey: 'h1',
  fullName: 'ws/mobile/shop_app',
  remote: 'git@bitbucket.org:ws/mobile/shop_app.git',
  defaultBaseBranch: 'main',
);

void main() {
  late MockReleasesRepository releases;
  late MockJobsRepository jobs;

  final review = reviewRelease();
  final all = [
    review,
    liveRelease,
    _of('prj_2', liveRelease),
    _of('prj_3', buildingRelease),
    _of('prj_3', release('rel_9', '1.0.0', 1, ReleaseState.merged)),
  ];

  setUp(() {
    releases = MockReleasesRepository();
    jobs = quietJobs();
    when(releases.watchReleases).thenAnswer((_) => Stream.value(Snapshot(all)));
    when(jobs.watchActiveRuns)
        .thenAnswer((_) => Stream.value(Snapshot([runningRun().run])));
  });

  group('HomeBloc', () {
    test('events compare by value', () {
      expect(const HomeSubscriptionRequested().props, isEmpty);
    });

    blocTest<HomeBloc, HomeState>(
      'follows the releases and the runs of every project',
      build: () => HomeBloc(releases: releases, jobs: jobs),
      act: (bloc) => bloc.add(const HomeSubscriptionRequested()),
      verify: (bloc) {
        final state = bloc.state;
        expect(state.loaded, isTrue);
        expect(state.liveOf('prj_1'), liveRelease);
        expect(state.inReviewOf('prj_1'), review);
        expect(state.liveOf('prj_3')?.state, ReleaseState.merged);
        expect(state.inReviewOf('prj_3'), isNull);
        expect(state.runningOf('prj_1'), 1);
        expect(state.runningOf('prj_2'), 0);
      },
    );

    blocTest<HomeBloc, HomeState>(
      'says what the engine said, and keeps going without the runs',
      setUp: () {
        when(releases.watchReleases)
            .thenAnswer((_) => Stream.error(const ConnectionException('away')));
        when(jobs.watchActiveRuns)
            .thenAnswer((_) => Stream.error(const ConnectionException('away')));
      },
      build: () => HomeBloc(releases: releases, jobs: jobs),
      act: (bloc) => bloc.add(const HomeSubscriptionRequested()),
      expect: () => [const HomeState(loaded: true, error: 'away')],
    );
  });

  testWidgets(
    'an owner with three projects sees what is live and in review in each',
    (tester) async {
      final shell = ShellCubit();
      await tester.pumpApp(
        const HomePage(),
        shell: shell,
        releasesRepository: releases,
        jobsRepository: jobs,
        projects: projectsIn(
          const ProjectsState(loaded: true, projects: [mataa, captain, _shop]),
        ),
        pendingApprovals: pendingIn(
          PendingApprovalsState(loaded: true, approvals: [pendingApproval]),
        ),
      );
      await tester.pump();

      expect(find.text('3 projects'), findsOneWidget);
      expect(find.text('Live: 5.3.7 (3200)'), findsNWidgets(2));
      expect(find.textContaining('5.4.1 (3283): '), findsOneWidget);
      expect(find.text('Live: 1.0.0 (1)'), findsOneWidget);
      expect(find.text('1 needs you'), findsOneWidget);
      expect(find.text('1 running'), findsOneWidget);

      await tester.tap(find.text('mataa_captain'));
      expect(shell.state, const ProjectDestination('prj_2'));
    },
  );

  testWidgets('says when nothing is live and when the engine failed', (
    tester,
  ) async {
    when(releases.watchReleases)
        .thenAnswer((_) => Stream.error(const ConnectionException('away')));
    await tester.pumpApp(
      const HomePage(),
      releasesRepository: releases,
      jobsRepository: jobs,
      projects: projectsIn(
        const ProjectsState(loaded: true, projects: [mataa]),
      ),
    );
    await tester.pump();

    expect(find.text('Nothing live yet'), findsOneWidget);
    expect(find.text('away'), findsOneWidget);
    when(releases.watchReleases)
        .thenAnswer((_) => Stream.value(const Snapshot(<Release>[])));
    await tester.tap(find.text('Retry'));
    await tester.pump();

    verify(releases.watchReleases).called(2);
    expect(find.text('away'), findsNothing);
  });

  testWidgets('waits for the projects, and shows NoProjects without', (
    tester,
  ) async {
    await tester.pumpApp(
      const HomePage(),
      projects: projectsIn(const ProjectsState()),
    );
    expect(find.byType(HomeView), findsNothing);
    await tester.pumpApp(
      const HomePage(),
      projects: projectsIn(const ProjectsState(loaded: true)),
    );
    expect(find.text('No projects yet'), findsWidgets);
  });
}

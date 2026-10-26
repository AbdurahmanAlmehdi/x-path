import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_desktop/job/job.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/project_overview/project_overview.dart';
import 'package:xp_desktop/projects/bloc/projects_bloc.dart';
import 'package:xp_desktop/shell/cubit/shell_cubit.dart';
import 'package:xp_repositories/xp_repositories.dart';

import '../dispatch/dispatch_harness.dart';
import '../helpers/job_fixtures.dart';
import '../helpers/pump_app.dart';
import '../helpers/release_fixtures.dart';
import 'overview_harness.dart';

void main() {
  setUpAll(() {
    registerJobFallbacksForOverview();
    registerDispatchFallbacks();
    registerFallbackValue(const ProjectsSubscriptionRequested());
  });

  group('ProjectOverviewPage', () {
    testWidgets('shows the release in flight, the ledger and the console', (
      tester,
    ) async {
      await OverviewHarness().pump(tester);
      expect(find.text('mataa_new_app'), findsOneWidget);
      expect(find.text('main · 1 app'), findsOneWidget);
      expect(find.text('Building'), findsOneWidget);
      expect(find.text('5.4.1 (3283)'), findsOneWidget);
      expect(find.text('prod · 9a3bc0d · started 14:02'), findsOneWidget);
      expect(find.text('BUILD'), findsOneWidget);
      expect(find.text('IN THE STORES · 5.4.1 (3283)'), findsOneWidget);
      expect(find.text('1 running'), findsOneWidget);
      expect(find.text('5.5.0 (3284)'), findsNWidgets(2));
      expect(find.text('Not uploaded'), findsNWidgets(3));
      expect(find.text('5.4.1 (3283) building'), findsOneWidget);
      expect(find.text('5.3.7'), findsNWidgets(2));
      expect(find.text('Ready for sale'), findsOneWidget);
      expect(find.text('Published'), findsOneWidget);
      expect(find.text('Verified'), findsOneWidget);
      expect(find.text('None'), findsOneWidget);
      expect(
        find.text('Running pod install...', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('lists the recent runs of the project', (tester) async {
      final shell = ShellCubit();
      await OverviewHarness(recentRuns: [failedRun().run])
          .pump(tester, shell: shell);

      expect(find.text('RECENT RUNS'), findsOneWidget);
      expect(find.text('Prod release'), findsWidgets);
      await tester.tap(find.text('All runs'));
      await tester.pump();
      expect(shell.state, const RunsDestination('prj_1'));
    });

    testWidgets('opens the job view of the release in flight', (tester) async {
      final shell = ShellCubit();
      await OverviewHarness().pump(tester, shell: shell);
      await tester.tap(find.text('Open job'));
      expect(shell.state, const JobDestination('run_1', projectId: 'prj_1'));
      await tester.tap(find.text('Build prod for android'));
      expect(
        shell.state,
        const JobDestination('run_1', jobId: 'job_android', projectId: 'prj_1'),
      );
    });

    testWidgets('opens the release in flight', (tester) async {
      final shell = ShellCubit();
      await OverviewHarness().pump(tester, shell: shell);
      await tester.tap(find.text('Open release'));
      expect(
        shell.state,
        const ReleasesDestination('prj_1', releaseId: 'rel_2'),
      );
    });

    testWidgets('filters the ledger by flavor', (tester) async {
      await OverviewHarness().pump(tester);
      await tester.tap(find.text('dev').first);
      await tester.pump();
      expect(find.text('com.mataaa.dev'), findsOneWidget);
      expect(find.text('com.sixdtec.mata · com.mataaa'), findsNothing);
    });

    testWidgets('dispatches and opens the run', (tester) async {
      final harness = OverviewHarness();
      final dispatch = DispatchHarness();
      when(() => dispatch.workflows.dispatch(any(), any(), any()))
          .thenAnswer((_) async => runningRun().run);
      final shell = ShellCubit();
      await tester.pumpApp(
        const ProjectOverviewPage('prj_1'),
        shell: shell,
        projectsRepository: harness.projects,
        releasesRepository: harness.releasesRepository,
        jobsRepository: harness.jobs,
        workflowsRepository: dispatch.workflows,
        runnersRepository: harness.runners,
        projects: projectsIn(
          ProjectsState(loaded: true, projects: [mataaWithVersion]),
        ),
      );
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(shell.state, const HomeDestination());

      await tester.tap(find.text('Dispatch…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dispatch 4 jobs'));
      await tester.pumpAndSettle();
      expect(shell.state, const JobDestination('run_1', projectId: 'prj_1'));
    });

    testWidgets('hides and shows the console', (tester) async {
      await OverviewHarness().pump(tester);
      expect(find.byType(LogView), findsOneWidget);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(find.byType(LogView), findsNothing);
      expect(find.text('· last: Build prod for ios'), findsOneWidget);
      await tester.tap(find.text('Console'));
      await tester.pump();
      expect(find.byType(LogView), findsOneWidget);
    });

    testWidgets('the console says what ran last when nothing runs', (
      tester,
    ) async {
      await OverviewHarness(run: failedRun()).pump(tester);
      expect(find.byType(LogView), findsNothing);
      expect(find.text('· last: Build prod for ios'), findsOneWidget);
      expect(find.text('Failed'), findsOneWidget);
    });

    testWidgets('shows the scan and scans again', (tester) async {
      final projects = projectsIn(
        ProjectsState(
          loaded: true,
          projects: [mataaWithVersion],
          error: 'Boom',
        ),
      );
      await OverviewHarness().pump(tester, projectsBloc: projects);
      await tester.tap(find.text('Scan'));
      await tester.pumpAndSettle();
      expect(find.text('Boom'), findsOneWidget);
      expect(find.text('Shorebird enabled for prod only'), findsOneWidget);
      await tester.tap(find.text('Scan again'));
      verify(() => projects.add(const ProjectScanRequested('prj_1'))).called(1);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(ScanDialog), findsNothing);
    });

    testWidgets('is read-only while the engine is away', (tester) async {
      final harness = DispatchHarness();
      final overview = OverviewHarness();
      await tester.pumpApp(
        const ProjectOverviewPage('prj_1'),
        connection: connectionIn(connectedTo(status: EngineStatus.unreachable)),
        projectsRepository: overview.projects,
        releasesRepository: overview.releasesRepository,
        jobsRepository: overview.jobs,
        workflowsRepository: harness.workflows,
        runnersRepository: overview.runners,
        projects: projectsIn(
          ProjectsState(loaded: true, projects: [mataaWithVersion]),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Dispatch…'));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      // No dispatch sheet opened: it would read the last workflow.
      verifyNever(() => harness.workflows.lastWorkflow(any()));
      await tester.tap(find.text('Scan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scan again'));
    });

    testWidgets('reads every state of the ledger', (tester) async {
      await OverviewHarness(
        releases: [
          release(
            'rel_3',
            '5.4.1',
            3283,
            ReleaseState.inReview,
            stores: [store(ReleaseStore.apple, StoreState.rejected)],
          ),
          release(
            'rel_4',
            '1.0.0',
            1,
            ReleaseState.approved,
            flavor: 'dev',
            stores: [
              store(ReleaseStore.apple, StoreState.approved),
              store(ReleaseStore.play, StoreState.approved),
            ],
          ),
        ],
        credentials: const [
          verifiedKey,
          Credential(
            id: 'crd_2',
            projectId: 'prj_1',
            app: '.',
            flavor: 'prod',
            kind: CredentialKind.playSa,
            status: CredentialStatus.unreachable,
          ),
          Credential(
            id: 'crd_3',
            projectId: 'prj_1',
            app: '.',
            flavor: 'dev',
            kind: CredentialKind.ascKey,
            status: CredentialStatus.rejected,
          ),
        ],
      ).pump(tester);
      expect(find.text('In review'), findsNWidgets(2));
      // The App Store lane of the hero and the ledger, and dev's credential.
      expect(find.text('Rejected'), findsNWidgets(3));
      expect(find.text('Pending developer release'), findsOneWidget);
      expect(find.text('Approved · not published'), findsOneWidget);
      expect(find.text('Not checked'), findsOneWidget);
      expect(find.text('no live release'), findsNWidgets(2));
    });

    testWidgets('a right click on a flavor copies its bundle ID', (
      tester,
    ) async {
      await OverviewHarness().pump(tester);

      await tester.tapAt(
        tester.getCenter(find.text('prod').last),
        buttons: kSecondaryButton,
      );
      await tester.pumpAndSettle();

      expect(find.text('Copy bundle ID com.sixdtec.mata'), findsOneWidget);
      expect(find.text('Copy bundle ID com.mataaa'), findsOneWidget);
    });

    testWidgets('sums up the credentials of each flavor and opens them', (
      tester,
    ) async {
      await OverviewHarness(
        credentials: const [
          Credential(
            id: 'crd_1',
            name: 'Team App Store key',
            projectId: 'prj_1',
            app: '.',
            flavor: 'prod',
            kind: CredentialKind.ascKey,
            status: CredentialStatus.verified,
          ),
          Credential(
            id: 'crd_2',
            projectId: 'prj_1',
            app: '.',
            flavor: 'prod',
            kind: CredentialKind.playSa,
            status: CredentialStatus.verified,
          ),
        ],
      ).pump(tester);
      expect(
        find.text('Team App Store key, Google Play service account'),
        findsOneWidget,
      );
      expect(find.text('Assign…'), findsOneWidget, reason: 'dev has none');
      await tester.tap(find.byKey(const Key('ledger.credentials...dev')));
      await tester.pumpAndSettle();
      expect(find.text('Credentials of dev'), findsOneWidget);
      expect(find.text('Not assigned'), findsNWidgets(7));
    });

    testWidgets('says what it cannot show', (tester) async {
      final harness = OverviewHarness();
      when(() => harness.releasesRepository.watchReleases(projectId: 'prj_1'))
          .thenAnswer(
            (_) => Stream.error(const ApiException('Boom.', statusCode: 500)),
          );
      await harness.pump(
        tester,
        project: const Project(
          id: 'prj_1',
          host: 'github.com',
          sourceKey: '1',
          githubRepoId: 1,
          fullName: 'acme/empty',
          remote: 'r',
          defaultBaseBranch: 'main',
        ),
      );
      expect(find.text('Boom.'), findsOneWidget);
      expect(find.text('No Flutter app found.'), findsOneWidget);
      expect(find.text('No release yet'), findsOneWidget);
    });

    testWidgets('counts the jobs that need you', (tester) async {
      final run = runningRun();
      await OverviewHarness(
        run: RunJobs(
          run: run.run,
          jobs: [
            for (final job in run.jobs)
              if (job.id == 'job_upload')
                Job(
                  id: job.id,
                  projectId: job.projectId,
                  workflowVersionId: job.workflowVersionId,
                  runId: job.runId,
                  name: job.name,
                  stage: job.stage,
                  state: JobState.waitingForApproval,
                  createdAt: job.createdAt,
                  steps: job.steps,
                )
              else
                job,
          ],
        ),
      ).pump(tester);
      expect(find.text('1 needs you'), findsOneWidget);
    });

    testWidgets('names every release and store state', (tester) async {
      await tester.pumpApp(const SizedBox());
      final l10n = tester.element(find.byType(SizedBox)).l10n;
      for (final state in ReleaseState.values) {
        expect(l10n.releaseState(state), isNotEmpty);
        expect(releaseStatus(state), isNotNull);
      }
      for (final store in ReleaseStore.values) {
        expect(l10n.storeName(store), isNotEmpty);
        for (final state in StoreState.values) {
          expect(l10n.storeState(store, state), isNotEmpty);
          expect(storeStatus(store, state), isNotNull);
        }
      }
    });

    testWidgets('shows the host of a project on another git host', (
      tester,
    ) async {
      await OverviewHarness().pump(tester, project: mataaOnBitbucket);

      expect(find.text('mataa_new_app'), findsOneWidget);
      expect(find.text('bitbucket.org · main · 1 app'), findsOneWidget);
      expect(find.text('main · 1 app'), findsNothing);
    });

    testWidgets('the scan says when it found nothing', (tester) async {
      await tester.pumpApp(
        const ScanDialog(projectId: 'prj_3'),
        projects: projectsIn(
          const ProjectsState(
            loaded: true,
            projects: [
              Project(
                id: 'prj_3',
                host: 'github.com',
                sourceKey: '3',
                githubRepoId: 3,
                fullName: 'acme/empty',
                remote: 'r',
                defaultBaseBranch: 'main',
              ),
            ],
          ),
        ),
      );
      expect(find.text('No Flutter app found.'), findsOneWidget);
      expect(find.text('Nothing to fix.'), findsOneWidget);
    });

    testWidgets('says when the project is gone', (tester) async {
      await tester.pumpApp(const ProjectOverviewPage('prj_9'));
      expect(
        find.text('This project is no longer on the engine.'),
        findsOneWidget,
      );
    });

    testWidgets('a hero in flight wins over what is live', (tester) async {
      await OverviewHarness(
        releases: [
          release(
            'rel_5',
            '5.3.6',
            3100,
            ReleaseState.approved,
            stores: [store(ReleaseStore.play, StoreState.live)],
          ),
        ],
      ).pump(tester);
      expect(find.text('Approved'), findsNWidgets(2));
    });

    testWidgets('a hero live in one store says which', (tester) async {
      await OverviewHarness(
        releases: [
          release(
            'rel_5',
            '5.3.6',
            3100,
            ReleaseState.live,
            stores: [store(ReleaseStore.play, StoreState.live)],
          ),
        ],
      ).pump(tester);
      expect(find.text('Live on Google Play'), findsOneWidget);
    });
  });
}

void registerJobFallbacksForOverview() =>
    registerFallbackValue(runningRun().run);

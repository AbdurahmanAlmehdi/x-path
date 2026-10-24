import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide StepState;
import 'package:mocktail/mocktail.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_desktop/job/job.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_desktop/shell/cubit/shell_cubit.dart';
import 'package:xp_desktop/widgets/widgets.dart';
import 'package:xp_repositories/xp_repositories.dart';

import '../helpers/engine_fixtures.dart';
import '../helpers/fakes.dart';
import '../helpers/job_fixtures.dart';
import '../helpers/pump_app.dart';
import 'job_harness.dart';

void main() {
  setUpAll(registerJobFallbacks);

  group('JobPage', () {
    testWidgets('shows the run, the job that runs and its log', (tester) async {
      await JobHarness().pump(tester);
      expect(find.text('Prod release'), findsOneWidget);
      expect(
        find.text('mataa_new_app · release/5.4.1 · 9a3bc0d'),
        findsOneWidget,
      );
      expect(find.text('Running'), findsOneWidget);
      expect(find.text('5.4.1 (3283)'), findsOneWidget);
      expect(find.text('elapsed 6m 55s · started 14:02'), findsOneWidget);
      expect(find.text('1 running'), findsOneWidget);
      expect(find.text('1 artifact'), findsOneWidget);
      expect(find.text('PREFLIGHT'), findsOneWidget);
      expect(find.text('linux-builder-01'), findsOneWidget);
      expect(
        find.text('BUILD PROD FOR IOS · THIS MAC · STEPS'),
        findsOneWidget,
      );
      expect(find.text('mataa.ipa'), findsOneWidget);
      expect(find.text('48.2 MB'), findsOneWidget);
      expect(
        find.text('Running pod install...', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('2 lines'), findsOneWidget);
      expect(find.text('Restart job'), findsNothing);
    });

    testWidgets('says what the engine answered without a run', (tester) async {
      final failing = JobHarness();
      when(() => failing.jobs.watchRunJobs('run_1')).thenAnswer(
        (_) =>
            Stream.error(const ApiException('No such run.', statusCode: 404)),
      );
      await failing.pump(tester);
      expect(find.text('No such run.'), findsOneWidget);
      expect(find.text('Job'), findsOneWidget);
      verify(() => failing.jobs.watchRunJobs('run_1')).called(1);

      await tester.tap(find.text('Retry'));
      await tester.pump();
      verify(() => failing.jobs.watchRunJobs('run_1')).called(1);
    });

    testWidgets('stands bars in while the run loads', (tester) async {
      final loading = JobHarness();
      when(() => loading.jobs.watchRunJobs('run_1'))
          .thenAnswer((_) => const Stream.empty());
      await loading.pump(tester);
      expect(find.byType(XpLoading), findsOneWidget);
    });

    testWidgets('shows another job when its node is clicked', (tester) async {
      final harness = JobHarness();
      await harness.pump(tester);
      await tester.tap(find.text('Build prod for android'));
      await tester.pump();
      await tester.pump();
      expect(
        find.text('BUILD PROD FOR ANDROID · LINUX-BUILDER-01 · STEPS'),
        findsOneWidget,
      );
      verify(() => harness.jobs.followLogs('job_android')).called(1);
    });

    testWidgets('cancels the run after asking', (tester) async {
      final harness = JobHarness();
      when(() => harness.jobs.cancelRun('run_1'))
          .thenAnswer((_) async => runningRun().run);
      await harness.pump(tester);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Cancel Prod release 5.4.1 (3283)?'), findsOneWidget);
      expect(
        find.text(
          'Build prod for ios stops now on This Mac (6m 12s in). Its partial '
          'output is discarded.',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'The 2 finished jobs keep their artifacts; Resume can reuse them.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('2 jobs that have not started will not run.'),
        findsOneWidget,
      );
      // Return does nothing.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(CancelRunDialog), findsOneWidget);
      await tester.tap(find.text('Keep running'));
      await tester.pumpAndSettle();
      verifyNever(() => harness.jobs.cancelRun(any()));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.period);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(find.byType(CancelRunDialog), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(CancelRunDialog), findsNothing);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel run'));
      await tester.pumpAndSettle();
      verify(() => harness.jobs.cancelRun('run_1')).called(1);
      expect(find.text('Run cancelled'), findsOneWidget);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.period);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.period);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      verify(() => harness.jobs.cancelRun('run_1')).called(1);
    });

    testWidgets('resumes an interrupted job', (tester) async {
      final harness = JobHarness(run: interruptedRun());
      when(
        () =>
            harness.jobs.resumeJob('job_ios', fromStep: any(named: 'fromStep')),
      ).thenAnswer((_) async => interruptedRun().jobs[1]);
      await harness.pump(tester);
      expect(find.text('Interrupted'), findsNWidgets(2));
      expect(
        find.textContaining('The engine stopped while this job ran.'),
        findsOneWidget,
      );
      expect(find.text('RESUME PLAN'), findsOneWidget);
      expect(find.text('First 2 steps'), findsOneWidget);
      expect(find.text('Build iOS and after'), findsOneWidget);

      await tester.tap(find.text('Restart job'));
      await tester.pump();
      verify(() => harness.jobs.resumeJob('job_ios', fromStep: 0)).called(1);

      await tester.tap(find.text('Resume from Build iOS'));
      await tester.pump();
      verify(() => harness.jobs.resumeJob('job_ios', fromStep: 2)).called(1);

      // A step before the first unfinished one can be picked.
      await tester.tap(find.text('Bump version').first);
      await tester.pump();
      expect(find.text('Resume from Bump version'), findsOneWidget);
      expect(find.text('Bump version and after'), findsOneWidget);
      // Picking it again lets go of it.
      await tester.tap(find.text('Bump version').first);
      await tester.pump();
      expect(find.text('Resume from Build iOS'), findsOneWidget);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      verify(() => harness.jobs.resumeJob('job_ios', fromStep: 0)).called(1);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      verify(() => harness.jobs.resumeJob('job_ios', fromStep: 2)).called(1);
    });

    testWidgets('says why a command failed', (tester) async {
      final harness = JobHarness(run: failedRun(), log: failedLog);
      when(() => harness.jobs.resumeJob('job_ios', fromStep: 0))
          .thenThrow(const ApiException('Not resumable.', statusCode: 409));
      await harness.pump(tester);
      await tester.tap(find.text('Restart job'));
      await tester.pump();
      expect(find.text('Not resumable.'), findsOneWidget);
    });

    testWidgets('names the runner of a job that runs remotely', (tester) async {
      final run = runningRun();
      final android = run.jobs[2];
      final remote = RunJobs(
        run: run.run,
        jobs: [
          for (final job in run.jobs)
            if (job.id == android.id)
              Job(
                id: job.id,
                projectId: job.projectId,
                workflowVersionId: job.workflowVersionId,
                runId: job.runId,
                name: job.name,
                stage: job.stage,
                state: JobState.running,
                runnerId: 'rnr_gone',
                startedAt: job.startedAt,
                createdAt: job.createdAt,
                steps: job.steps,
              )
            else
              job,
        ],
      );
      await JobHarness(run: remote).pump(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Build prod for android stops now on rnr_gone'),
        findsOneWidget,
      );
    });

    testWidgets('follows the log again once a resumed job runs', (
      tester,
    ) async {
      final harness = JobHarness(run: interruptedRun());
      await harness.pump(tester);
      harness.logs.single.add(const LogEndFrame(state: JobState.interrupted));
      await harness.logs.single.close();
      await tester.pump();
      harness.runs.add(Snapshot(runningRun()));
      await tester.pump();
      await tester.pump();
      verify(() => harness.jobs.followLogs('job_ios', after: 220)).called(1);
    });

    testWidgets('says that a side effect waits for a resume', (tester) async {
      final run = runningRun(
        iosState: JobState.waitingForResume,
        buildState: StepState.interrupted,
      );
      await JobHarness(run: run).pump(tester);
      expect(
        find.textContaining('The engine stopped during Build iOS'),
        findsOneWidget,
      );
    });

    testWidgets('shows where a failed run failed and jumps to the error', (
      tester,
    ) async {
      await JobHarness(run: failedRun(), log: failedLog).pump(tester);
      expect(find.text('Failed at Build iOS'), findsOneWidget);
      expect(find.text('ran 6m 30s · started 14:02'), findsOneWidget);
      await tester.tap(find.text('Jump to error'));
      await tester.pump();
      await tester.tap(find.byType(LogView));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      expect(
        find.text(
          '*** Error: Error exporting the archive.',
          findRichText: true,
        ),
        findsOneWidget,
      );
    });

    testWidgets('says why a failed job failed without hovering', (
      tester,
    ) async {
      final run = failedRun();
      Job withMessages(Job job) => Job(
        id: job.id,
        projectId: job.projectId,
        workflowVersionId: job.workflowVersionId,
        runId: job.runId,
        name: job.name,
        stage: job.stage,
        state: job.state,
        startedAt: job.startedAt,
        finishedAt: job.finishedAt,
        createdAt: job.createdAt,
        message: 'Build iOS failed.',
        steps: [
          for (final step in job.steps)
            JobStep(
              ordinal: step.ordinal,
              kind: step.kind,
              state: step.state,
              sideEffect: step.sideEffect,
              attempts: step.attempts,
              startedAt: step.startedAt,
              finishedAt: step.finishedAt,
              message: step.state == StepState.failed
                  ? 'xcodebuild exited with 65.'
                  : null,
            ),
        ],
      );
      final failed = RunJobs(
        run: run.run,
        jobs: [
          for (final job in run.jobs)
            if (job.id == 'job_ios') withMessages(job) else job,
        ],
      );
      await JobHarness(run: failed, log: failedLog).pump(tester);
      expect(
        find.text('xcodebuild exited with 65. Build iOS failed.'),
        findsOneWidget,
      );
      expect(find.text('Failed'), findsWidgets);

      expect(failureOf(run.jobs[1]), isNull);
      expect(
        failureOf(
          job(
            'j',
            'j',
            0,
            JobState.failed,
            message: 'Same.',
            steps: const [
              JobStep(
                ordinal: 0,
                kind: 'command',
                state: StepState.failed,
                sideEffect: false,
                attempts: 1,
                message: 'Same.',
              ),
            ],
          ),
        ),
        'Same.',
      );
    });

    testWidgets('says why a queued job waits', (tester) async {
      final run = runningRun();
      final waiting = RunJobs(
        run: run.run,
        jobs: [
          for (final candidate in run.jobs)
            if (candidate.id == 'job_upload')
              job(
                'job_upload',
                'Upload prod for ios',
                2,
                JobState.queued,
                message: 'No runner can do ios-sign.',
              )
            else
              candidate,
        ],
      );
      await JobHarness(run: waiting).pump(tester, jobId: 'job_upload');
      expect(find.text('Waiting: No runner can do ios-sign.'), findsOneWidget);
    });

    testWidgets('is read-only while the engine is away', (tester) async {
      final harness = JobHarness(run: interruptedRun());
      await harness.pump(
        tester,
        connection: connectionIn(connectedTo(status: EngineStatus.unreachable)),
      );
      await tester.tap(find.text('Restart job'));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      for (final key in [LogicalKeyboardKey.keyR, LogicalKeyboardKey.period]) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(key);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      }
      await tester.pumpAndSettle();
      expect(find.byType(CancelRunDialog), findsNothing);
      verifyNever(
        () => harness.jobs.resumeJob(any(), fromStep: any(named: 'fromStep')),
      );
    });

    testWidgets('opens the test results of a job that ran its tests', (
      tester,
    ) async {
      final shell = ShellCubit();
      final tests = job(
        'job_tests',
        'Tests dev',
        0,
        JobState.failed,
        start: local(14, 2),
        end: local(14, 4, 41),
        steps: [
          step(
            0,
            'test',
            StepState.failed,
            start: local(14, 2),
            end: local(14, 4, 41),
          ),
        ],
      );
      final harness = JobHarness(
        run: RunJobs(run: runningRun().run, jobs: [tests]),
      );
      await harness.pump(tester, shell: shell);
      await tester.tap(find.text('Test results'));
      expect(shell.state, const TestsDestination('prj_1', jobId: 'job_tests'));
      expect(
        hasTestResults(
          job(
            'j',
            'n',
            0,
            JobState.running,
            steps: [step(0, 'test', StepState.running)],
          ),
        ),
        isFalse,
      );
      expect(
        hasTestResults(
          job(
            'j',
            'n',
            0,
            JobState.succeeded,
            steps: [step(0, 'test', StepState.succeeded)],
          ),
        ),
        isTrue,
      );
    });

    testWidgets(
      'a failed run is run again, or its failed jobs, and says what it made',
      (tester) async {
        final harness = JobHarness(run: failedRun());
        final shell = ShellCubit();
        when(() => harness.jobs.rerunFailed('run_1'))
            .thenAnswer((_) async => failedRun().run);
        when(() => harness.jobs.runAgain('run_1')).thenAnswer(
          (_) async => Run(
            id: 'run_2',
            projectId: 'prj_1',
            workflowId: 'wf_prod',
            workflowVersionId: 'wfv_1',
            sha: 'a' * 40,
            state: RunState.queued,
            locksProject: true,
            createdAt: at,
            jobs: const [],
          ),
        );
        when(() => harness.workflows.getWorkflow(any(), any())).thenAnswer(
          (_) async => Workflow(
            id: 'wf_prod',
            projectId: 'prj_1',
            name: 'Prod release',
            builtin: true,
            version: WorkflowVersionInfo(
              id: 'wfv_2',
              version: 2,
              createdAt: at,
            ),
            versions: [
              ...prodWorkflow.versions,
              WorkflowVersionInfo(id: 'wfv_2', version: 2, createdAt: at),
            ],
            yaml: workflowYaml,
          ),
        );
        await harness.pump(tester, shell: shell);

        expect(find.text('VERSION'), findsOneWidget);
        expect(find.text('3283'), findsOneWidget);
        expect(
          find.text(
            'Run again runs version 1 of the workflow, the one this run ran; '
            'it has version 2 now.',
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('Re-run failed jobs'));
        await tester.pump();
        verify(() => harness.jobs.rerunFailed('run_1')).called(1);

        await tester.tap(find.text('Run again'));
        await tester.pump();
        await tester.pump();
        expect(shell.state, const JobDestination('run_2', projectId: 'prj_1'));
      },
    );

    testWidgets('downloads an artifact, then reveals it', (tester) async {
      final revealed = <String>[];
      final harness = JobHarness(
        run: runningRun(
          iosState: JobState.succeeded,
          buildState: StepState.succeeded,
          runState: RunState.succeeded,
          iosEnd: local(14, 8, 30),
        ),
      );
      when(() => harness.jobs.downloadArtifact('art_1')).thenAnswer(
        (_) async => ArtifactDownload(content: Stream.value([1]), sha256: null),
      );
      await harness.pump(
        tester,
        services: testServices(
          saveDownload: (name, content) async => '/Downloads/$name',
          revealFile: (path) async => revealed.add(path),
        ),
      );
      await tester.tap(find.byTooltip('Download…'));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byTooltip('Reveal in Finder'));
      await tester.pump();
      expect(revealed, ['/Downloads/mataa.ipa']);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.tap(find.byTooltip('Copy path'));
      await tester.pump();
      expect(copied, '/Downloads/mataa.ipa');
      expect(find.text('Copied the path'), findsOneWidget);
    });

    testWidgets(
      'a finished run sums up its jobs and tests, and links to the stores',
      (tester) async {
        final opened = <Uri>[];
        final testsJob = job(
          'job_tests',
          'Tests prod',
          0,
          JobState.succeeded,
          steps: [step(0, 'test', StepState.succeeded)],
        );
        final ran = runningRun(runState: RunState.succeeded).run;
        final run = Run(
          id: ran.id,
          projectId: ran.projectId,
          workflowId: ran.workflowId,
          workflowVersionId: ran.workflowVersionId,
          sha: ran.sha,
          state: RunState.succeeded,
          locksProject: true,
          createdAt: ran.createdAt,
          jobs: const [],
          request: const DispatchRequest(flavors: ['prod']),
        );
        final prod = mataa.profile.apps.single.flavors.first;
        final withAppleId = Project(
          id: mataa.id,
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
                  FlavorProfile(
                    name: prod.name,
                    entrypoint: prod.entrypoint,
                    prod: true,
                    androidAppId: prod.androidAppId,
                    appleAppId: '1234567890',
                  ),
                ],
              ),
            ],
          ),
        );
        final tests = MockTestsRepository();
        when(() => tests.watchRun('job_tests'))
            .thenAnswer((_) => Stream.value(Snapshot(devRun)));
        final harness = JobHarness(
          run: RunJobs(run: run, jobs: [testsJob]),
        );
        await harness.pump(
          tester,
          tests: tests,
          project: withAppleId,
          services: testServices(openUrl: (url) async => opened.add(url)),
        );
        await tester.pump();

        expect(find.text('JOBS'), findsOneWidget);
        expect(find.text('1 succeeded'), findsOneWidget);
        expect(find.text('TESTS'), findsOneWidget);
        expect(
          find.text('1284 passed · 27 failed · 3 skipped'),
          findsOneWidget,
        );
        expect(find.text('FLAVORS'), findsOneWidget);
        await tester.tap(find.text('App Store Connect · prod'));
        await tester.tap(find.text('Google Play · prod'));
        expect(opened, [
          Uri.parse('https://appstoreconnect.apple.com/apps/1234567890'),
          Uri.parse('https://play.google.com/store/apps/details?id=com.mataaa'),
        ]);
      },
    );

    test('links to the stores of each flavor it ran for', () {
      final ran = runningRun(runState: RunState.succeeded).run;
      Run asked(List<String>? flavors) => Run(
        id: ran.id,
        projectId: ran.projectId,
        workflowId: ran.workflowId,
        workflowVersionId: ran.workflowVersionId,
        sha: ran.sha,
        state: RunState.succeeded,
        locksProject: true,
        createdAt: ran.createdAt,
        jobs: const [],
        request: DispatchRequest(flavors: flavors),
      );
      final withIds = Project(
        id: mataa.id,
        githubRepoId: mataa.githubRepoId,
        fullName: mataa.fullName,
        remote: mataa.remote,
        defaultBaseBranch: mataa.defaultBaseBranch,
        profile: const ProjectProfile(
          apps: [
            AppProfile(
              name: 'app',
              path: '.',
              hasIos: true,
              hasAndroid: true,
              flavors: [
                FlavorProfile(
                  name: 'prod',
                  entrypoint: 'lib/main.dart',
                  prod: true,
                  androidAppId: 'com.a',
                  appleAppId: '123',
                ),
                FlavorProfile(
                  name: 'dev',
                  entrypoint: 'lib/main_dev.dart',
                  androidAppId: 'com.a.dev',
                  appleAppId: '456',
                ),
              ],
            ),
          ],
        ),
      );

      expect(
        [
          for (final link in storeLinks(asked(['dev']), withIds)) '${link.url}',
        ],
        ['https://appstoreconnect.apple.com/apps/456'],
        reason: 'Google Play only for a production flavor',
      );
      expect(storeLinks(asked(null), withIds), hasLength(3));
      expect(storeLinks(asked(null), null), isEmpty);
      expect(storeLinks(runningRun().run, withIds), isEmpty);
    });

    testWidgets('a finished run offers to run again only', (tester) async {
      final run = runningRun(
        iosState: JobState.succeeded,
        buildState: StepState.succeeded,
        runState: RunState.succeeded,
        iosEnd: local(14, 8, 30),
      );
      final done = RunJobs(
        run: run.run,
        jobs: [
          for (final job in run.jobs)
            if (job.state == JobState.queued)
              Job(
                id: job.id,
                projectId: job.projectId,
                workflowVersionId: job.workflowVersionId,
                runId: job.runId,
                name: job.name,
                stage: job.stage,
                state: JobState.succeeded,
                createdAt: job.createdAt,
                steps: const [],
              )
            else
              job,
        ],
      );
      final harness = JobHarness(run: done);
      await harness.pump(tester);
      expect(find.text('Succeeded'), findsOneWidget);
      expect(find.text('Cancel'), findsNothing);
      expect(find.text('Run again'), findsOneWidget);
      expect(find.text('Re-run failed jobs'), findsNothing);
      for (final key in [LogicalKeyboardKey.keyR, LogicalKeyboardKey.period]) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(key);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      }
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();
      expect(find.byType(CancelRunDialog), findsNothing);
    });
  });

  group('heroOf', () {
    testWidgets('names every state of a run', (tester) async {
      await tester.pumpApp(const SizedBox());
      final l10n = tester.element(find.byType(SizedBox)).l10n;
      String hero(RunState state) => heroOf(
        RunJobs(
          run: Run(
            id: 'r',
            projectId: 'p',
            workflowId: 'w',
            workflowVersionId: 'v',
            sha: sha,
            state: state,
            locksProject: false,
            createdAt: local(14, 2),
            jobs: const [],
          ),
          jobs: [
            if (state == RunState.failed) job('j', 'j', 0, JobState.failed),
          ],
        ),
        l10n,
      ).$2;
      expect(hero(RunState.queued), 'Queued');
      expect(hero(RunState.running), 'Running');
      expect(hero(RunState.waitingForApproval), 'Waiting for approval');
      expect(hero(RunState.succeeded), 'Succeeded');
      expect(hero(RunState.cancelled), 'Cancelled');
      expect(hero(RunState.failed), 'Failed');
    });
  });
}

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide StepState;
import 'package:mocktail/mocktail.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_desktop/job/job.dart';
import 'package:xp_desktop/l10n/l10n.dart';
import 'package:xp_repositories/xp_repositories.dart';

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
      expect(find.text('Re-run all'), findsNothing);
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

      await tester.tap(find.text('Re-run all'));
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
      await tester.tap(find.text('Re-run all'));
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

    testWidgets('is read-only while the engine is away', (tester) async {
      final harness = JobHarness(run: interruptedRun());
      await harness.pump(
        tester,
        connection: connectionIn(connectedTo(status: EngineStatus.unreachable)),
      );
      await tester.tap(find.text('Re-run all'));
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

    testWidgets('a finished run offers nothing to do', (tester) async {
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

import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show SizedBox;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_desktop/app/app.dart';
import 'package:xp_desktop/app/bloc/engine_notices_bloc.dart';
import 'package:xp_desktop/approvals/approvals.dart';
import 'package:xp_desktop/dispatch/dispatch.dart';
import 'package:xp_desktop/projects/bloc/projects_bloc.dart';
import 'package:xp_desktop/shell/shell.dart';
import 'package:xp_macos_services/testing.dart';
import 'package:xp_macos_services/xp_macos_services.dart';
import 'package:xp_repositories/xp_repositories.dart';

import '../dispatch/dispatch_harness.dart';
import '../helpers/approval_fixtures.dart';
import '../helpers/fakes.dart';
import '../helpers/job_fixtures.dart';
import '../helpers/pump_app.dart';
import '../project_overview/overview_harness.dart';

void main() {
  late MockApprovalsRepository approvals;

  setUp(() {
    approvals = quietApprovals();
    when(() => approvals.watchApproval(any()))
        .thenAnswer((_) => Stream.value(Snapshot(pendingApproval)));
  });

  final soon = Approval(
    id: 'apr_5',
    projectId: 'prj_1',
    action: 'prod_patch',
    sha: pendingApproval.sha,
    version: '5.4.1+3283',
    state: ApprovalState.pending,
    createdAt: pendingApproval.createdAt,
    expiresAt: DateTime(2026, 10, 13, 14, 40).toUtc(),
  );

  Future<void> sendShortcut(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
    await tester.pumpAndSettle();
  }

  group('NeedsYouBar', () {
    Future<void> pump(
      WidgetTester tester,
      List<Approval> pending, {
      ShellCubit? shell,
      EngineStatus status = EngineStatus.connected,
    }) => tester.pumpApp(
      const NeedsYouBar(projectId: 'prj_1'),
      shell: shell,
      approvalsRepository: approvals,
      connection: connectionIn(connectedTo(status: status)),
      pendingApprovals: pendingIn(
        PendingApprovalsState(loaded: true, approvals: pending),
      ),
    );

    testWidgets('shows nothing when nothing waits', (tester) async {
      await pump(tester, [mergeApproval]);
      expect(find.text('NEEDS YOU'), findsNothing);
    });

    testWidgets('shows what expires first, and the rest in the inbox', (
      tester,
    ) async {
      final shell = ShellCubit();
      await pump(tester, [pendingApproval, soon], shell: shell);
      expect(find.text('NEEDS YOU'), findsOneWidget);
      expect(find.text('Patch 5.4.1 (3283)'), findsOneWidget);
      expect(find.text('9a3bc0d · expires in 31m'), findsOneWidget);
      await tester.tap(find.text('+1 more'));
      expect(shell.state, const ApprovalsDestination());
    });

    testWidgets('Review… and Deny… open the confirmation sheet', (
      tester,
    ) async {
      await pump(tester, [pendingApproval]);
      await tester.tap(find.text('Review…'));
      await tester.pumpAndSettle();
      expect(find.text('Return never approves. ⌘↩ approves.'), findsOne);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Deny…'));
      await tester.pumpAndSettle();
      expect(find.text('REASON (OPTIONAL)'), findsOneWidget);
    });

    testWidgets('Deny… is read-only while the engine is away', (tester) async {
      await pump(tester, [pendingApproval], status: EngineStatus.unreachable);
      await tester.tap(find.text('Deny…'));
      await tester.pumpAndSettle();
      expect(find.text('REASON (OPTIONAL)'), findsNothing);
    });
  });

  group('⇧⌘A', () {
    Future<void> pump(
      WidgetTester tester,
      ShellCubit shell,
      List<Approval> pending,
    ) => tester.pumpApp(
      const AppShell(),
      shell: shell,
      approvalsRepository: approvals,
      projectsRepository: quietProjects(),
      projects: projectsIn(
        ProjectsState(loaded: true, projects: [mataaWithVersion]),
      ),
      pendingApprovals: pendingIn(
        PendingApprovalsState(loaded: true, approvals: pending),
      ),
    );

    testWidgets('reviews what the shown project waits for', (tester) async {
      await pump(tester, ShellCubit(), [pendingApproval]);
      await tester.pump();
      await sendShortcut(tester);
      expect(find.text('Return never approves. ⌘↩ approves.'), findsOne);
    });

    testWidgets('opens the inbox when the project waits for nothing', (
      tester,
    ) async {
      final shell = ShellCubit();
      await pump(tester, shell, [mergeApproval]);
      await tester.pump();
      await sendShortcut(tester);
      expect(shell.state, const ApprovalsDestination());
    });
  });

  group('NeedsYouAlertsListener', () {
    late StreamController<Snapshot<List<Approval>>> pending;
    late FakeNeedsYouAlerts alerts;
    late PendingApprovalsBloc bloc;
    late ShellCubit shell;

    setUp(() {
      pending = StreamController<Snapshot<List<Approval>>>();
      alerts = FakeNeedsYouAlerts();
      shell = ShellCubit();
      when(() => approvals.watchApprovals(state: ApprovalState.pending))
          .thenAnswer((_) => pending.stream);
    });

    tearDown(() => unawaited(pending.close()));

    Future<void> pump(
      WidgetTester tester, {
      EngineNoticesBloc? notices,
      AppPreferences? preferences,
      JobsRepository? jobs,
      WorkflowsRepository? workflows,
    }) async {
      bloc = PendingApprovalsBloc(approvals: approvals)
        ..add(const PendingApprovalsSubscriptionRequested());
      addTearDown(() => unawaited(bloc.close()));
      await tester.pumpApp(
        const NeedsYouAlertsListener(child: SizedBox()),
        services: testServices(alerts: alerts, preferences: preferences),
        shell: shell,
        approvalsRepository: approvals,
        jobsRepository: jobs,
        workflowsRepository: workflows,
        pendingApprovals: bloc,
        notices: notices,
        projects: projectsIn(
          ProjectsState(loaded: true, projects: [mataaWithVersion]),
        ),
      );
    }

    testWidgets('notifies what starts waiting, and keeps the menu bar', (
      tester,
    ) async {
      await pump(tester);
      pending.add(Snapshot([pendingApproval], cached: true));
      await tester.pump();
      expect(alerts.menus.last.header, 'Needs you · 1');
      pending.add(Snapshot([pendingApproval]));
      await tester.pump();
      // What waited before the engine answered is not notified.
      expect(alerts.notices, isEmpty);

      pending.add(Snapshot([mergeApproval, pendingApproval]));
      await tester.pump();
      expect(alerts.notices.single.approvalId, 'apr_2');
      expect(alerts.notices.single.title, 'Approve the merge');
      expect(alerts.notices.single.body, 'prj_2 · 9a3bc0d · expires in 0m');
      expect(alerts.notices.single.review, 'Review…');
      final menu = alerts.menus.last;
      expect(menu.tooltip, 'XPath: 2 need you');
      expect(menu.items.first.title, 'Review: Approve the merge…');
      expect(menu.items.last.detail, startsWith('mataa_new_app · 9a3bc0d · '));
      expect(menu.openApp, 'Open XPath');

      pending.add(const Snapshot([]));
      await tester.pump();
      expect(alerts.withdrawn, ['apr_2', 'apr_1']);
      expect(alerts.menus.last.header, 'Nothing needs you');
      expect(alerts.menus.last.tooltip, 'XPath');
      expect(alerts.menus.last.needsYou, isFalse);
    });

    testWidgets('notices what the engine says, unless it is turned off', (
      tester,
    ) async {
      final notices = StreamController<EngineNoticesState>();
      addTearDown(notices.close);
      final noticesBloc = MockEngineNoticesBloc();
      whenListen(
        noticesBloc,
        notices.stream,
        initialState: const EngineNoticesState(),
      );
      await pump(
        tester,
        notices: noticesBloc,
        preferences: AppPreferences({
          'mutedNotices': ['jobSucceeded'],
        }),
      );
      final run = runningRun().run;

      for (final (count, notice) in [
        (
          1,
          const EngineRaisedNotice(
            NoticeKind.jobFailed,
            NotificationRaised(
              kind: NotificationKind.jobFailed,
              level: NotificationLevel.error,
              title: 'Build prod failed',
              body: 'mataa · prod',
              jobId: 'job_1',
            ),
          ),
        ),
        (
          2,
          const EngineRaisedNotice(
            NoticeKind.jobSucceeded,
            NotificationRaised(
              kind: NotificationKind.jobSucceeded,
              level: NotificationLevel.success,
              title: 'Muted',
              body: '',
            ),
          ),
        ),
        (
          3,
          const RunnerLostNotice(
            RunnerLeaseLost(
              runnerId: 'rnr_1',
              jobId: 'job_2',
              projectId: 'prj_1',
              reason: 'lapsed',
              state: JobState.queued,
            ),
          ),
        ),
        (4, const CapabilityLostNotice(runner: 'mac', lost: ['ios-sign'])),
        (
          5,
          JobWaitingNotice(
            run: run,
            jobId: 'job_3',
            jobName: 'Build prod for ios',
            reason: 'No runner can do ios-sign.',
          ),
        ),
      ]) {
        notices.add(
          EngineNoticesState(running: [run], notice: notice, count: count),
        );
        await tester.pump();
      }

      expect(alerts.engineNotices, [
        const EngineNotice(
          target: 'job:job_1',
          title: 'Build prod failed',
          body: 'mataa · prod',
        ),
        const EngineNotice(
          target: 'job:job_2',
          title: 'A runner lost a job',
          body: 'Its lease ran out, so the job is queued again.',
        ),
        const EngineNotice(
          target: 'runners',
          title: 'mac can no longer do ios-sign',
          body: 'Jobs that need it wait for another runner.',
        ),
        EngineNotice(
          target: 'run:${run.id}:prj_1:job_3',
          title: 'A job waits for a runner',
          body:
              'Build prod for ios has waited 10 minutes: No runner can do '
              'ios-sign.',
        ),
      ]);
      final menu = alerts.menus.last;
      expect(menu.runningHeader, 'Running · 1');
      expect(menu.running.single.target, 'run:${run.id}:prj_1');
      expect(menu.running.single.detail, startsWith('mataa_new_app · '));
      expect(menu.dispatch, 'Dispatch…');
      expect(menu.projects.single.projectId, 'prj_1');
    });

    testWidgets('a notice or a running run opens what it names', (
      tester,
    ) async {
      final jobs = quietJobs();
      when(() => jobs.watchJob('job_1'))
          .thenAnswer((_) => Stream.value(Snapshot(runningRun().jobs.first)));
      when(() => jobs.watchJob('job_gone'))
          .thenAnswer((_) => Stream.error(const ConnectionException('gone')));
      await pump(tester, jobs: jobs);

      Future<ShellDestination> open(String target) async {
        alerts.act(ShowNotice(target));
        await tester.pump();
        await tester.pump();
        return shell.state;
      }

      final job = runningRun().jobs.first;
      expect(
        await open('job:job_1'),
        JobDestination(job.runId!, jobId: job.id, projectId: job.projectId),
      );
      expect(
        await open('run:run_9:prj_1'),
        const JobDestination('run_9', projectId: 'prj_1'),
      );
      expect(
        await open('run:run_9:prj_1:job_9'),
        const JobDestination('run_9', jobId: 'job_9', projectId: 'prj_1'),
      );
      expect(
        await open('release:prj_1:rel_1'),
        const ReleasesDestination('prj_1', releaseId: 'rel_1'),
      );
      expect(
        await open('credentials:prj_1'),
        const CredentialsDestination('prj_1'),
      );
      expect(await open('runners'), const RunnersDestination());
      expect(await open('settings'), const SettingsDestination());
      expect(
        await open('job:job_gone'),
        const SettingsDestination(),
        reason: 'a job that is gone opens nothing',
      );
    });

    testWidgets('quick dispatch opens the dispatch sheet', (tester) async {
      await pump(tester, workflows: DispatchHarness().workflows);

      alerts
        ..act(const DispatchProject('prj_nope'))
        ..act(const DispatchProject('prj_1'));
      await tester.pumpAndSettle();

      expect(find.byType(DispatchSheet), findsOneWidget);
    });

    testWidgets('Review… opens the sheet; the notification opens the inbox', (
      tester,
    ) async {
      await pump(tester);
      alerts.act(const ReviewApproval('apr_1'));
      await tester.pumpAndSettle();
      expect(find.text('Return never approves. ⌘↩ approves.'), findsOne);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      alerts.act(const ShowApproval('apr_1'));
      await tester.pump();
      expect(shell.state, const ApprovalsDestination(approvalId: 'apr_1'));
      alerts.act(const OpenApp());
      await tester.pump();
      expect(shell.state, const ApprovalsDestination(approvalId: 'apr_1'));
    });
  });
}

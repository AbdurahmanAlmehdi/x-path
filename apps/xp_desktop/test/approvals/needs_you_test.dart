import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show SizedBox;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/approvals/approvals.dart';
import 'package:xp_desktop/projects/bloc/projects_bloc.dart';
import 'package:xp_desktop/shell/shell.dart';
import 'package:xp_macos_services/testing.dart';
import 'package:xp_macos_services/xp_macos_services.dart';
import 'package:xp_repositories/xp_repositories.dart';

import '../helpers/approval_fixtures.dart';
import '../helpers/fakes.dart';
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

    Future<void> pump(WidgetTester tester) async {
      bloc = PendingApprovalsBloc(approvals: approvals)
        ..add(const PendingApprovalsSubscriptionRequested());
      addTearDown(() => unawaited(bloc.close()));
      await tester.pumpApp(
        const NeedsYouAlertsListener(child: SizedBox()),
        services: testServices(alerts: alerts),
        shell: shell,
        approvalsRepository: approvals,
        pendingApprovals: bloc,
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

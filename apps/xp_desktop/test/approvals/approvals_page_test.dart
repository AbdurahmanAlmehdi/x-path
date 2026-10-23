import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_desktop/approvals/approvals.dart';
import 'package:xp_desktop/projects/bloc/projects_bloc.dart';
import 'package:xp_repositories/xp_repositories.dart';

import '../helpers/approval_fixtures.dart';
import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';
import '../helpers/release_fixtures.dart';
import '../project_overview/overview_harness.dart';

void main() {
  late MockApprovalsRepository approvals;
  late MockJobsRepository jobs;
  late MockReleasesRepository releases;

  final expired = decided(
    Approval(
      id: 'apr_3',
      projectId: 'prj_1',
      action: 'push',
      sha: pendingApproval.sha,
      version: '5.4.1+3283',
      state: ApprovalState.pending,
      createdAt: pendingApproval.createdAt,
      expiresAt: pendingApproval.expiresAt,
    ),
    state: ApprovalState.expired,
  );
  final denied = decided(
    Approval(
      id: 'apr_4',
      projectId: 'prj_1',
      action: 'prod_release',
      sha: pendingApproval.sha,
      version: '5.4.1+3283',
      state: ApprovalState.pending,
      createdAt: pendingApproval.createdAt,
      expiresAt: pendingApproval.expiresAt,
    ),
    state: ApprovalState.denied,
    reason: 'Not today',
  );

  setUp(() {
    approvals = quietApprovals();
    jobs = MockJobsRepository();
    releases = MockReleasesRepository();
    when(approvals.watchApprovals).thenAnswer(
      (_) => Stream.value(
        Snapshot([pendingApproval, mergeApproval, expired, denied]),
      ),
    );
    when(() => approvals.watchApproval(any()))
        .thenAnswer((_) => Stream.value(Snapshot(pendingApproval)));
    when(() => jobs.watchJob('job_upload'))
        .thenAnswer((_) => Stream.value(Snapshot(uploadJob)));
    when(() => releases.watchRelease('rel_2'))
        .thenAnswer((_) => Stream.value(Snapshot(reviewRelease())));
  });

  Future<void> pump(
    WidgetTester tester, {
    String? approvalId,
    EngineStatus status = EngineStatus.connected,
  }) async {
    await tester.pumpApp(
      ApprovalsPage(approvalId: approvalId),
      approvalsRepository: approvals,
      jobsRepository: jobs,
      releasesRepository: releases,
      connection: connectionIn(connectedTo(status: status)),
      projects: projectsIn(
        ProjectsState(loaded: true, projects: [mataaWithVersion]),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
  }

  testWidgets('lists what waits and shows the first', (tester) async {
    await pump(tester);
    expect(find.text('This Mac · 2 pending'), findsOneWidget);
    expect(find.text('PENDING · 2'), findsOneWidget);
    expect(find.text('Submit 5.4.1 (3283) to the stores'), findsNWidgets(2));
    expect(find.text('Approve the merge'), findsOneWidget);
    expect(find.text('IF YOU APPROVE'), findsOneWidget);
    expect(find.text('expires in 21m'), findsOneWidget);

    await tester.tap(find.text('Approve the merge'));
    await tester.pump();
    expect(find.text('Approve the merge'), findsNWidgets(2));
    expect(find.text('prj_2'), findsOneWidget);
  });

  testWidgets('filters decided and expired requests', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Decided'));
    await tester.pump();
    expect(find.text('Release 5.4.1 (3283) to the stores'), findsNWidgets(2));
    expect(find.text('by Mac mini · Oct 13 14:05'), findsOneWidget);
    expect(find.text('Not today'), findsOneWidget);
    expect(find.text('IF YOU APPROVE'), findsNothing);

    await tester.tap(find.text('Expired'));
    await tester.pump();
    expect(find.text('Push 5.4.1 (3283) to GitHub'), findsNWidgets(2));
  });

  testWidgets('opens at the approval asked for', (tester) async {
    await pump(tester, approvalId: 'apr_3');
    expect(find.text('Push 5.4.1 (3283) to GitHub'), findsNWidgets(2));
  });

  testWidgets('Approve… and ⇧⌘A open the confirmation sheet', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Approve…'));
    await tester.pumpAndSettle();
    expect(find.text('Return never approves. ⌘↩ approves.'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
    await tester.pumpAndSettle();
    expect(find.text('Return never approves. ⌘↩ approves.'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Deny…'));
    await tester.pumpAndSettle();
    expect(find.text('REASON (OPTIONAL)'), findsOneWidget);
  });

  testWidgets('⇧⌘A does nothing on a settled approval', (tester) async {
    await pump(tester, approvalId: 'apr_3');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
    await tester.pumpAndSettle();
    expect(find.text('Return never approves. ⌘↩ approves.'), findsNothing);
  });

  testWidgets('says when nothing waits, and what failed', (tester) async {
    when(approvals.watchApprovals)
        .thenAnswer((_) => Stream.value(const Snapshot([])));
    await pump(tester, status: EngineStatus.unreachable);
    expect(find.text('Nothing is waiting'), findsOneWidget);
    await tester.tap(find.text('Expired'));
    await tester.pump();
    expect(find.text('Nothing here'), findsOneWidget);

    when(approvals.watchApprovals).thenAnswer(
      (_) => Stream.error(const ApiException('Nope.', statusCode: 500)),
    );
    await tester.pumpApp(
      const ApprovalsPage(approvalId: 'x'),
      approvalsRepository: approvals,
    );
    await tester.pump();
    expect(find.text('Nope.'), findsOneWidget);
  });

  testWidgets('Approve… and Deny… are read-only while the engine is away', (
    tester,
  ) async {
    await pump(tester, status: EngineStatus.unreachable);
    await tester.tap(find.text('Deny…'));
    await tester.pumpAndSettle();
    expect(find.text('REASON (OPTIONAL)'), findsNothing);
    await tester.tap(find.text('Approve…'));
    await tester.pumpAndSettle();
    expect(find.text('Return never approves. ⌘↩ approves.'), findsNothing);
  });
}

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_desktop/approvals/approvals.dart';
import 'package:xp_desktop/projects/bloc/projects_bloc.dart';
import 'package:xp_desktop/shell/cubit/shell_cubit.dart';
import 'package:xp_repositories/xp_repositories.dart';

import '../helpers/approval_fixtures.dart';
import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';
import '../helpers/release_fixtures.dart';
import '../project_overview/overview_harness.dart';

/// The repositories behind a confirmation sheet of [pendingApproval].
class ReviewHarness {
  new() {
    when(() => approvals.watchApproval('apr_1'))
        .thenAnswer((_) => approval.stream);
    when(() => jobs.watchJob('job_upload'))
        .thenAnswer((_) => Stream.value(Snapshot(uploadJob)));
    when(() => releases.watchRelease('rel_2'))
        .thenAnswer((_) => Stream.value(Snapshot(reviewRelease())));
  }

  final MockApprovalsRepository approvals = quietApprovals();
  final jobs = MockJobsRepository();
  final releases = MockReleasesRepository();
  final approval = StreamController<Snapshot<Approval>>.broadcast();

  /// Opens the sheet from a button, at the denial if [deny].
  Future<void> open(
    WidgetTester tester, {
    bool deny = false,
    ShellCubit? shell,
    EngineStatus status = EngineStatus.connected,
  }) async {
    await tester.pumpApp(
      Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => showApprovalReview(context, 'apr_1', deny: deny),
            child: const Text('Open'),
          ),
        ),
      ),
      shell: shell,
      connection: connectionIn(connectedTo(status: status)),
      approvalsRepository: approvals,
      jobsRepository: jobs,
      releasesRepository: releases,
      projects: projectsIn(
        ProjectsState(loaded: true, projects: [mataaWithVersion]),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    approval.add(Snapshot(pendingApproval));
    await tester.pump();
    await tester.pump();
  }
}

void main() {
  late ReviewHarness harness;

  setUp(() => harness = ReviewHarness());
  tearDown(() => unawaited(harness.approval.close()));

  Future<void> arm(WidgetTester tester) =>
      tester.pump(approvalArmingDelay + const Duration(milliseconds: 10));

  testWidgets('shows what the approval is bound to and what it does', (
    tester,
  ) async {
    await harness.open(tester);
    expect(find.text('Submit 5.4.1 (3283) to the stores'), findsOneWidget);
    expect(find.text('expires in 23h 51m · Oct 13 14:00'), findsOneWidget);
    expect(find.text('com.sixdtec.mata'), findsOneWidget);
    expect(find.text('Upload prod'), findsOneWidget);
    expect(find.text(' · Approval waits for this'), findsOneWidget);
    expect(find.text('Project gate “store submission”'), findsOneWidget);
    expect(
      find.textContaining('XPath uploads the builds made from 9a3bc0d'),
      findsOneWidget,
    );
    expect(
      find.textContaining('It goes out as prod · com.sixdtec.mata'),
      findsOneWidget,
    );
    expect(
      find.text(
        'If the commit, version or flavor change before then, this approval '
        'is void.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Return never approves; ⌘↩ approves once armed', (tester) async {
    when(() => harness.approvals.approve('apr_1'))
        .thenAnswer((_) async => decided(pendingApproval));
    await harness.open(tester);

    // Before the arming delay ⌘↩ does nothing.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
    await tester.pump();
    verifyNever(() => harness.approvals.approve(any()));

    await arm(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
    await tester.pump();
    verifyNever(() => harness.approvals.approve(any()));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
    await tester.pumpAndSettle();
    verify(() => harness.approvals.approve('apr_1')).called(1);
    expect(find.text('Submit 5.4.1 (3283) to the stores'), findsNothing);
  });

  testWidgets('approves with a click once armed', (tester) async {
    when(() => harness.approvals.approve('apr_1'))
        .thenAnswer((_) async => decided(pendingApproval));
    await harness.open(tester);
    await arm(tester);
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    verify(() => harness.approvals.approve('apr_1')).called(1);
  });

  testWidgets('says when another device decided first', (tester) async {
    when(() => harness.approvals.approve('apr_1')).thenThrow(
      ApprovalAlreadyDecided(
        'Decided already.',
        approval: decided(pendingApproval, state: ApprovalState.denied),
      ),
    );
    await harness.open(tester);
    await arm(tester);
    await tester.tap(find.text('Approve'));
    await tester.pump();
    expect(
      find.text(
        'Already denied by Mac mini. The first decision counts; nothing to do '
        'here.',
      ),
      findsOneWidget,
    );
    expect(find.text('Approve'), findsNothing);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('says when it expired meanwhile', (tester) async {
    await harness.open(tester);
    harness.approval.add(
      Snapshot(decided(pendingApproval, state: ApprovalState.expired)),
    );
    await tester.pump();
    expect(find.textContaining('This approval expired'), findsOneWidget);
    expect(find.textContaining('expired Oct 14 14:00'), findsOneWidget);
  });

  testWidgets('denies with a reason, or goes back', (tester) async {
    when(() => harness.approvals.deny('apr_1', reason: 'Wrong build'))
        .thenAnswer((_) async => decided(pendingApproval));
    await harness.open(tester);
    await tester.tap(find.text('Deny…'));
    await tester.pump();
    expect(find.text('REASON (OPTIONAL)'), findsOneWidget);
    await tester.tap(find.text('Back'));
    await tester.pump();
    expect(find.text('REASON (OPTIONAL)'), findsNothing);

    await tester.tap(find.text('Deny…'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Wrong build');
    await tester.tap(find.text('Deny'));
    await tester.pumpAndSettle();
    verify(() => harness.approvals.deny('apr_1', reason: 'Wrong build'))
        .called(1);
  });

  testWidgets('opens at the denial, and shows what the engine refused', (
    tester,
  ) async {
    when(() => harness.approvals.deny('apr_1'))
        .thenThrow(const ConnectionException('Connection refused.'));
    await harness.open(tester, deny: true);
    await tester.tap(find.text('Deny'));
    await tester.pump();
    expect(find.text('Connection refused.'), findsOneWidget);
  });

  testWidgets('is read-only while the engine is away', (tester) async {
    await harness.open(tester, status: EngineStatus.unreachable);
    await arm(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
    await tester.tap(find.text('Approve'));
    await tester.pump();
    verifyNever(() => harness.approvals.approve(any()));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('opens the job that waits', (tester) async {
    final shell = ShellCubit();
    await harness.open(tester, shell: shell);
    await tester.tap(find.text('Upload prod'));
    await tester.pumpAndSettle();
    expect(
      shell.state,
      const JobDestination('run_1', jobId: 'job_upload', projectId: 'prj_1'),
    );
  });

  testWidgets('says when the approval cannot be read', (tester) async {
    await harness.open(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    final failing = ReviewHarness();
    when(() => failing.approvals.watchApproval('apr_1')).thenAnswer(
      (_) => Stream.error(
        const ApiException('No such approval.', statusCode: 404),
      ),
    );
    await failing.open(tester);
    expect(find.text('No such approval.'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
  });
}

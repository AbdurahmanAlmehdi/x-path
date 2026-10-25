import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_desktop/dispatch/dispatch.dart';
import 'package:xp_repositories/xp_repositories.dart';

import '../helpers/fakes.dart';
import '../helpers/job_fixtures.dart';
import '../helpers/pump_app.dart';
import 'dispatch_harness.dart';

void main() {
  setUpAll(registerDispatchFallbacks);

  Future<void> commandReturn(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pumpAndSettle();
  }

  group('DispatchSheet', () {
    testWidgets('previews where each job lands and which gates it hits', (
      tester,
    ) async {
      await DispatchHarness().open(tester);
      expect(find.text('Dispatch'), findsOneWidget);
      expect(find.text('mataa_new_app · Mataa customer app'), findsOneWidget);
      expect(find.text('built-in · gated'), findsOneWidget);
      expect(find.text('WILL RUN · 4 JOBS IN 3 STAGES'), findsOneWidget);
      expect(find.text('This Mac'), findsOneWidget);
      expect(
        find.text('This Mac first, else linux-builder-01 · slot 2 of 4'),
        findsOneWidget,
      );
      expect(find.text('1 job on This Mac'), findsNWidgets(2));
      expect(find.text('Upload approval'), findsOneWidget);
      expect(
        find.text('waits for your approval: store submission'),
        findsOneWidget,
      );
      expect(
        find.text('from 5.4.1 (3283) in the pubspec at the last scan'),
        findsOneWidget,
      );
      expect(find.text('Dispatch 4 jobs'), findsOneWidget);
      expect(find.text('Return does not dispatch'), findsOneWidget);
    });

    testWidgets('greys out a workflow that needs GitHub, with the reason', (
      tester,
    ) async {
      final harness = DispatchHarness();
      when(() => harness.workflows.getWorkflow(any(), any())).thenAnswer(
        (_) async => Workflow(
          id: 'wf_prod',
          projectId: 'prj_3',
          name: 'Prod release',
          builtin: true,
          version: prodWorkflow.version,
          versions: prodWorkflow.versions,
          yaml: '$releaseYaml          - kind: git.push\n',
        ),
      );
      await harness.open(tester, project: shop);

      expect(find.text('shop_app · Shop'), findsOneWidget);
      expect(
        find.text(
          'This workflow cannot run here: its git.push step works only on '
          'GitHub, and this project is on bitbucket.org. Run one without '
          'GitHub steps, such as dev-build or test.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Dispatch 4 jobs'));
      await commandReturn(tester);
      verifyNever(() => harness.workflows.dispatch(any(), any(), any()));
    });

    testWidgets('Return does not dispatch; ⌘↩ does', (tester) async {
      final harness = DispatchHarness();
      when(() => harness.workflows.dispatch('prj_1', 'wf_prod', any()))
          .thenAnswer((_) async => runningRun().run);
      await harness.open(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      verifyNever(() => harness.workflows.dispatch(any(), any(), any()));
      expect(find.byType(DispatchSheet), findsOneWidget);

      await commandReturn(tester);
      verify(
        () => harness.workflows.dispatch(
          'prj_1',
          'wf_prod',
          const DispatchRequest(app: '.', ref: 'main', bump: VersionBump.keep),
        ),
      ).called(1);
      expect(find.byType(DispatchSheet), findsNothing);
      expect(harness.result, runningRun().run);
    });

    testWidgets('dispatches with the button', (tester) async {
      final harness = DispatchHarness();
      when(() => harness.workflows.dispatch('prj_1', 'wf_prod', any()))
          .thenAnswer((_) async => runningRun().run);
      await harness.open(tester);
      await tester.tap(find.text('Dispatch 4 jobs'));
      await tester.pumpAndSettle();
      expect(harness.result, runningRun().run);
    });

    testWidgets('changes what it previews', (tester) async {
      final harness = DispatchHarness();
      await harness.open(tester);
      await tester.tap(find.text('dev'));
      await tester.tap(find.text('iOS'));
      await tester.tap(find.text('Android'));
      await tester.tap(find.text('Android'));
      await tester.tap(find.text('Tag'));
      await tester.tap(find.text('Minor'));
      await tester.enterText(find.byType(TextField), 'release/5.4.1');
      await tester.pumpAndSettle();
      verify(
        () => harness.workflows.preview(
          project: any(named: 'project'),
          workflow: any(named: 'workflow'),
          request: const DispatchRequest(
            app: '.',
            ref: 'release/5.4.1',
            flavors: ['prod', 'dev'],
            platforms: ['android'],
            bump: VersionBump.minor,
          ),
        ),
      ).called(greaterThanOrEqualTo(1));

      await tester.tap(find.text('Prod release'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dev build').last);
      await tester.pumpAndSettle();
      verify(() => harness.workflows.getWorkflow('prj_1', 'wf_dev')).called(1);
    });

    testWidgets('closes with Escape or Cancel', (tester) async {
      final harness = DispatchHarness();
      await harness.open(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(harness.closed, isTrue);
      expect(harness.result, isNull);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(DispatchSheet), findsNothing);
    });

    testWidgets('picks the app of a project with several', (tester) async {
      final harness = DispatchHarness();
      await harness.open(tester, project: captain);
      expect(find.text('APP'), findsOneWidget);
      await tester.tap(find.text('captain').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('tablet').last);
      await tester.pumpAndSettle();
      verify(
        () => harness.workflows.preview(
          project: any(named: 'project'),
          workflow: any(named: 'workflow'),
          request: const DispatchRequest(
            app: 'apps/tablet',
            ref: 'main',
            bump: VersionBump.keep,
          ),
        ),
      ).called(greaterThanOrEqualTo(1));
    });

    testWidgets('says what went wrong and when nothing would run', (
      tester,
    ) async {
      final harness = DispatchHarness();
      when(
        () => harness.workflows.preview(
          project: any(named: 'project'),
          workflow: any(named: 'workflow'),
          request: any(named: 'request'),
        ),
      ).thenAnswer(
        (_) async =>
            const DispatchPreview(flavors: [], platforms: [], stages: []),
      );
      await harness.open(tester);
      expect(
        find.text('Nothing would run for these flavors and platforms.'),
        findsOneWidget,
      );
      expect(find.text('Dispatch 0 jobs'), findsOneWidget);

      when(() => harness.workflows.listWorkflows('prj_1'))
          .thenThrow(const ConnectionException('Connection refused.'));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Connection refused.'), findsOneWidget);
      expect(find.text('The project has no workflow.'), findsOneWidget);
    });

    testWidgets('is read-only while the engine is away', (tester) async {
      final harness = DispatchHarness();
      await harness.open(
        tester,
        connection: connectionIn(connectedTo(status: EngineStatus.unreachable)),
      );
      await tester.tap(find.text('Dispatch 4 jobs'));
      await commandReturn(tester);
      verifyNever(() => harness.workflows.dispatch(any(), any(), any()));
    });
  });
}

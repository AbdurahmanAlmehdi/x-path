import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_desktop/dispatch/dispatch.dart';
import 'package:xp_desktop/widgets/widgets.dart';
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

  group('inputs (UX-04)', () {
    Workflow typed(List<WorkflowInput> inputs) => Workflow(
      id: 'wf_prod',
      projectId: 'prj_1',
      name: 'shorebird-patch',
      builtin: true,
      version: prodWorkflow.version,
      versions: prodWorkflow.versions,
      yaml: 'stages: []',
      inputs: inputs,
    );

    Release release(String version, int build, int day) => Release(
      id: 'rel_$build',
      projectId: 'prj_1',
      app: '.',
      flavor: 'prod',
      version: version,
      build: build,
      state: ReleaseState.live,
      stores: const [],
      builds: const [],
      mergeEnabled: false,
      createdAt: DateTime.utc(2026, 10, day),
      updatedAt: DateTime.utc(2026, 10, day),
    );

    MockReleasesRepository releasesOf(List<Release> releases) {
      final repository = MockReleasesRepository();
      when(() => repository.watchReleases(projectId: any(named: 'projectId')))
          .thenAnswer((_) => Stream.value(Snapshot(releases)));
      return repository;
    }

    Finder text(String input) => find.descendant(
      of: find.byKey(Key('dispatch.input.$input')),
      matching: find.byType(TextField),
    );

    testWidgets('a patch dispatches after picking a release', (tester) async {
      final harness = DispatchHarness();
      when(() => harness.workflows.getWorkflow(any(), any())).thenAnswer(
        (_) async => typed(const [
          WorkflowInput(
            name: 'releaseVersion',
            type: InputType.release,
            description: 'The release the patch applies to.',
          ),
          WorkflowInput(
            name: 'allowNativeDiffs',
            type: InputType.boolean,
            defaultValue: false,
          ),
          WorkflowInput(
            name: 'track',
            type: InputType.choice,
            options: ['internal', 'beta'],
            required: true,
          ),
        ]),
      );
      when(() => harness.workflows.dispatch('prj_1', 'wf_prod', any()))
          .thenAnswer((_) async => runningRun().run);
      await harness.open(
        tester,
        releases: releasesOf([
          release('5.4.0', 3200, 1),
          release('5.4.1', 3283, 9),
        ]),
      );

      expect(find.text('INPUTS'), findsOneWidget);
      expect(find.text('The release the patch applies to.'), findsOneWidget);
      expect(find.text('5.4.1 (3283) · prod'), findsOneWidget);
      await tester.tap(find.text('5.4.1 (3283) · prod'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('5.4.0 (3200) · prod').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('internal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('beta').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dispatch 4 jobs'));
      await tester.pumpAndSettle();

      final request =
          verify(
                () => harness.workflows.dispatch(
                  'prj_1',
                  'wf_prod',
                  captureAny(),
                ),
              ).captured.single
              as DispatchRequest;
      expect(request.releaseVersion, '5.4.0+3200');
      expect(request.inputs, {
        'releaseVersion': '5.4.0+3200',
        'allowNativeDiffs': true,
        'track': 'beta',
      });
    });

    testWidgets('a release input waits for a release', (tester) async {
      final harness = DispatchHarness();
      when(() => harness.workflows.getWorkflow(any(), any())).thenAnswer(
        (_) async => typed(const [
          WorkflowInput(name: 'releaseVersion', type: InputType.release),
        ]),
      );
      await harness.open(tester, releases: releasesOf(const []));

      expect(
        find.text(
          'No releases yet: this workflow needs a release that reached a '
          'store.',
        ),
        findsOneWidget,
      );
      final button = tester.widget<XpButton>(
        find.widgetWithText(XpButton, 'Dispatch 4 jobs'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('a dev build uploads to a Firebase app id typed in the sheet', (
      tester,
    ) async {
      final harness = DispatchHarness();
      when(() => harness.workflows.getWorkflow(any(), any())).thenAnswer(
        (_) async => typed(const [
          WorkflowInput(name: 'firebaseAppIds', type: InputType.json),
          WorkflowInput(
            name: 'notes',
            type: InputType.string,
            defaultValue: 'Default notes',
          ),
          WorkflowInput(name: 'loose'),
        ]),
      );
      when(() => harness.workflows.dispatch('prj_1', 'wf_prod', any()))
          .thenAnswer((_) async => runningRun().run);
      await harness.open(tester);

      expect(
        tester.widget<TextField>(text('notes')).controller!.text,
        'Default notes',
      );
      await tester.enterText(text('firebaseAppIds'), '{"dev": ');
      await tester.pumpAndSettle();
      expect(find.text('Not valid JSON.'), findsOneWidget);
      expect(
        tester
            .widget<XpButton>(find.widgetWithText(XpButton, 'Dispatch 4 jobs'))
            .onPressed,
        isNull,
      );
      await tester.enterText(
        text('firebaseAppIds'),
        '{"dev": {"android": "1:1:android:a"}}',
      );
      await tester.enterText(text('loose'), 'true');
      await tester.enterText(text('notes'), '');
      await tester.pumpAndSettle();
      expect(find.text('Not valid JSON.'), findsNothing);
      await tester.enterText(text('firebaseAppIds'), ' ');
      await tester.enterText(
        text('firebaseAppIds'),
        '{"dev": {"android": "1:1:android:a"}}',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dispatch 4 jobs'));
      await tester.pumpAndSettle();

      final request =
          verify(
                () => harness.workflows.dispatch(
                  'prj_1',
                  'wf_prod',
                  captureAny(),
                ),
              ).captured.single
              as DispatchRequest;
      expect(request.inputs, {
        'firebaseAppIds': {
          'dev': {'android': '1:1:android:a'},
        },
        'loose': 'true',
      });
    });

    testWidgets('types a version instead of a bump', (tester) async {
      final harness = DispatchHarness();
      when(() => harness.workflows.dispatch('prj_1', 'wf_prod', any()))
          .thenAnswer((_) async => runningRun().run);
      await harness.open(tester);

      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('dispatch.version')),
          matching: find.byType(TextField),
        ),
        '6.0.0',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dispatch 4 jobs'));
      await tester.pumpAndSettle();

      final request =
          verify(
                () => harness.workflows.dispatch(
                  'prj_1',
                  'wf_prod',
                  captureAny(),
                ),
              ).captured.single
              as DispatchRequest;
      expect(request.version, '6.0.0');
      expect(request.bump, isNull);
    });
  });
}

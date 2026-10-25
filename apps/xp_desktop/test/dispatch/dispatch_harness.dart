import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/app/app.dart';
import 'package:xp_desktop/dispatch/view/dispatch_sheet.dart';
import 'package:xp_repositories/xp_repositories.dart';

import '../helpers/fakes.dart';
import '../helpers/job_fixtures.dart';
import '../helpers/pump_app.dart';
import '../project_overview/overview_harness.dart';

final prodSummary = WorkflowSummary(
  id: 'wf_prod',
  projectId: 'prj_1',
  name: 'Prod release',
  builtin: true,
  version: prodWorkflow.version,
);

final devSummary = WorkflowSummary(
  id: 'wf_dev',
  projectId: 'prj_1',
  name: 'Dev build',
  builtin: true,
  version: prodWorkflow.version,
);

const releaseYaml = '''
lock: project
stages:
  - name: prepare
    jobs:
      prepare:
        steps:
          - kind: version.bump
          - kind: git.releaseBranch
            gate: prod_release
''';

/// What the engine plans for the production release of `Dispatch-Sheet`:
/// two build jobs on the engine or a runner, then an upload that waits for
/// an approval and a tag on the engine; the iOS upload is left out.
const releasePreview = DispatchPlan(
  flavors: ['prod'],
  platforms: ['android', 'ios'],
  currentVersion: '5.4.1+3283',
  version: '5.4.1',
  build: 3284,
  stages: [
    PlannedStage(
      name: 'build',
      jobs: [
        PlannedJob(
          name: 'Build prod for ios',
          flavor: 'prod',
          platform: 'ios',
          capabilities: ['flutter', 'ios-sign'],
          engineOnly: false,
          local: true,
        ),
        PlannedJob(
          name: 'Build prod for android',
          flavor: 'prod',
          platform: 'android',
          capabilities: ['android', 'flutter'],
          engineOnly: false,
          local: true,
          runner: 'linux-builder-01',
        ),
      ],
    ),
    PlannedStage(
      name: 'upload',
      gates: ['store_submission'],
      jobs: [PlannedJob(name: 'Upload prod', engineOnly: true, local: true)],
    ),
    PlannedStage(
      name: 'finalize',
      jobs: [PlannedJob(name: 'Tag prod', engineOnly: true, local: true)],
    ),
  ],
  skipped: [
    SkippedJob(
      name: 'Upload prod for ios',
      stage: 'upload',
      flavor: 'prod',
      platform: 'ios',
      reason: 'no App Store app id for prod',
    ),
  ],
);

/// A page with a button that opens the Dispatch sheet, over a mocked
/// workflows repository.
class DispatchHarness {
  new() {
    registerDispatchFallbacks();
    when(() => workflows.listWorkflows(any()))
        .thenAnswer((_) async => [prodSummary, devSummary]);
    when(() => workflows.getWorkflow(any(), any())).thenAnswer(
      (_) async => Workflow(
        id: 'wf_prod',
        projectId: 'prj_1',
        name: 'Prod release',
        builtin: true,
        version: prodWorkflow.version,
        versions: prodWorkflow.versions,
        yaml: releaseYaml,
      ),
    );
    when(() => workflows.workflowOf(any()))
        .thenAnswer((_) async => prodWorkflow);
    when(() => workflows.plan(any(), any(), any()))
        .thenAnswer((_) async => releasePreview);
    when(() => workflows.lastWorkflow(any())).thenAnswer((_) async => null);
    when(() => workflows.lastInputs(any(), any()))
        .thenAnswer((_) async => const {});
    when(() => workflows.rememberDispatch(any(), any(), any()))
        .thenAnswer((_) async {});
  }

  final workflows = MockWorkflowsRepository();
  Run? result;
  bool closed = false;

  Future<void> open(
    WidgetTester tester, {
    Project? project,
    EngineConnectionBloc? connection,
    ReleasesRepository? releases,
  }) async {
    await tester.pumpApp(
      Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () async {
              result = await showDispatchSheet(
                context,
                project ?? mataaWithVersion,
              );
              closed = true;
            },
            child: const Text('Open'),
          ),
        ),
      ),
      connection: connection,
      workflowsRepository: workflows,
      releasesRepository: releases,
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }
}

void registerDispatchFallbacks() {
  registerFallbackValue(mataa);
  registerFallbackValue(prodWorkflow);
  registerFallbackValue(const DispatchRequest());
  registerFallbackValue(runningRun().run);
}

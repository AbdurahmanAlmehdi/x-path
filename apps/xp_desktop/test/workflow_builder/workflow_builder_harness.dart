import 'package:flutter/widgets.dart' show Brightness;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/app/app_services.dart';
import 'package:xp_desktop/projects/bloc/projects_bloc.dart';
import 'package:xp_desktop/workflow_builder/workflow_builder.dart';

import '../helpers/fakes.dart';
import '../helpers/pump_app.dart';

final created = DateTime.utc(2026, 10, 13, 9);

WorkflowVersionInfo versionInfo(int version) => WorkflowVersionInfo(
  id: 'wfv_$version',
  version: version,
  createdAt: created,
);

/// A workflow of the owner's: a check stage, then a matrix build with a
/// gated step.
const releaseYaml = r'''
schema: 1
name: Store release
description: Builds and uploads the prod flavor.
lock: project
inputs:
  notes:
    description: Release notes.
    default: ''
stages:
  - name: check
    jobs:
      check:
        steps:
          - kind: git.checkout
          - kind: guard
            with:
              checks: [source, credentials]
  - name: build
    jobs:
      build:
        name: Build ${{ flavor.name }} for ${{ platform }}
        matrix:
          platform: ${{ platforms }}
          flavor: [prod]
        if: flavor.prod
        capabilities: [flutter]
        steps:
          - kind: git.checkout
          - kind: build.android
            if: platform == 'android'
            with:
              artifact: aab
          - kind: upload.play
            gate: store_submission
            with:
              track: internal
''';

final releaseWorkflow = Workflow(
  id: 'wf_mine',
  projectId: 'prj_1',
  name: 'store-release',
  builtin: false,
  version: versionInfo(2),
  versions: [versionInfo(1), versionInfo(2)],
  yaml: releaseYaml,
);

final devBuild = Workflow(
  id: 'wf_dev',
  projectId: 'prj_1',
  name: 'dev-build',
  builtin: true,
  version: versionInfo(1),
  versions: [versionInfo(1)],
  yaml:
      'schema: 1\nname: Dev build\nstages:\n  - name: build\n    jobs:\n'
      '      build:\n        steps:\n          - kind: git.checkout\n',
);

WorkflowSummary summaryOf(Workflow workflow) => WorkflowSummary(
  id: workflow.id,
  projectId: workflow.projectId,
  name: workflow.name,
  builtin: workflow.builtin,
  version: workflow.version,
);

const schema = WorkflowSchema(
  schema: 1,
  steps: [
    StepType(kind: 'build.android', withKeys: ['artifact', 'obfuscate']),
    StepType(kind: 'command', withKeys: ['run']),
    StepType(kind: 'git.checkout', withKeys: ['commitFrom']),
    StepType(kind: 'guard', withKeys: ['checks']),
    StepType(kind: 'upload.play', withKeys: ['artifactsFrom', 'track']),
  ],
  gates: ['prod_release', 'push', 'store_submission'],
  capabilities: ['android', 'flutter', 'ios-sign'],
  matrixAxes: ['platform', 'flavor'],
  platforms: ['android', 'ios'],
);

/// A workflows repository over [releaseWorkflow] and [devBuild], whose
/// engine finds no issue.
MockWorkflowsRepository workflowsRepository() {
  final repository = MockWorkflowsRepository();
  when(
    () => repository.listWorkflows('prj_1'),
  ).thenAnswer((_) async => [summaryOf(devBuild), summaryOf(releaseWorkflow)]);
  when(repository.schema).thenAnswer((_) async => schema);
  when(() => repository.getWorkflow('prj_1', 'wf_mine'))
      .thenAnswer((_) async => releaseWorkflow);
  when(() => repository.getWorkflow('prj_1', 'wf_dev'))
      .thenAnswer((_) async => devBuild);
  when(() => repository.validate('prj_1', any()))
      .thenAnswer((_) async => const ValidateWorkflowResponse(valid: true));
  return repository;
}

/// Pumps the builder of `prj_1` over [repository] and lets it load.
Future<void> pumpBuilder(
  WidgetTester tester, {
  MockWorkflowsRepository? repository,
  String? workflowId,
  Brightness brightness = Brightness.light,
  FilePicker? pickFile,
  FileSaver? saveFile,
}) async {
  await tester.pumpApp(
    WorkflowBuilderPage(projectId: 'prj_1', workflowId: workflowId),
    workflowsRepository: repository ?? workflowsRepository(),
    services: testServices(pickFile: pickFile, saveFile: saveFile),
    brightness: brightness,
    projects: projectsIn(const ProjectsState(loaded: true, projects: [mataa])),
  );
  await settle(tester);
}

/// Lets the loads and the debounced check finish.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
}

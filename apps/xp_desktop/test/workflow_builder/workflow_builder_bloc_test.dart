import 'dart:convert';
import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_desktop/app/app_services.dart';
import 'package:xp_desktop/workflow_builder/workflow_builder.dart';
import 'package:xp_repositories/xp_repositories.dart';

import '../helpers/fakes.dart';
import 'workflow_builder_harness.dart';

void main() {
  late MockWorkflowsRepository workflows;
  PickedFile? picked;
  Exception? saveError;
  final saved = <(String, String)>[];

  setUp(() {
    workflows = workflowsRepository();
    picked = null;
    saveError = null;
    saved.clear();
  });

  WorkflowBuilderBloc build() => WorkflowBuilderBloc(
    workflows: workflows,
    projectId: 'prj_1',
    pickFile: () async => picked,
    saveFile: (name, contents) async {
      if (saveError case final error?) throw error;
      saved.add((name, contents));
      return '/tmp/$name';
    },
    debounce: Duration.zero,
  );

  /// The bloc with [releaseWorkflow] open and checked.
  Future<WorkflowBuilderBloc> opened() async {
    final bloc = build()..add(const WorkflowBuilderStarted());
    await bloc.stream.firstWhere(
      (state) => state.validation == WorkflowValidation.valid,
    );
    return bloc;
  }

  test('events and notices compare by value', () {
    expect(const WorkflowBuilderStarted(workflowId: 'a').props, ['a']);
    expect(const WorkflowOpened('a').props, ['a']);
    expect(const WorkflowDraftStarted().props, isEmpty);
    expect(const WorkflowImportRequested().props, isEmpty);
    expect(const WorkflowExportRequested().props, isEmpty);
    expect(const WorkflowYamlChanged('y').props, ['y']);
    expect(const WorkflowDocumentEdited(WorkflowDocument()).props, const [
      WorkflowDocument(),
      null,
    ]);
    expect(
      const WorkflowSelectionChanged(WorkflowSelection.workflow).props,
      const [WorkflowSelection.workflow],
    );
    expect(const WorkflowSaveRequested(name: 'n').props, ['n']);
    expect(const WorkflowSavedNotice('n', 2).props, ['n', 2]);
    expect(const WorkflowExportedNotice('/p').props, ['/p']);
  });

  group('the state', () {
    test('lists every issue once, by place', () {
      const a = WorkflowIssue(line: 2, column: 4, message: 'a');
      const b = WorkflowIssue(line: 2, column: 1, message: 'b');
      const c = WorkflowIssue(line: 1, column: 9, message: 'c');
      const state = WorkflowBuilderState(
        shapeIssues: [a],
        engineIssues: [a, b, c],
      );
      expect(state.issues, [c, b, a]);
    });

    test('says what saving does and whether it is needed', () {
      expect(const WorkflowBuilderState().savesAsNew, isTrue);
      expect(const WorkflowBuilderState(yaml: 'x').dirty, isTrue);
      expect(WorkflowBuilderState(workflow: devBuild).savesAsNew, isTrue);
      final mine = WorkflowBuilderState(workflow: releaseWorkflow);
      expect(mine.savesAsNew, isFalse);
      expect(mine.name, 'store-release');
      expect(const WorkflowBuilderState(draftName: 'x').name, 'x');
      expect(const WorkflowBuilderState().editable, isFalse);
      expect(
        const WorkflowBuilderState(document: WorkflowDocument()).editable,
        isTrue,
      );
    });
  });

  group('starting', () {
    test(
      'opens the first workflow of the owner, reads it and checks it',
      () async {
        final bloc = await opened();

        final state = bloc.state;
        expect(state.loaded, isTrue);
        expect(state.workflows.map((w) => w.id), ['wf_dev', 'wf_mine']);
        expect(state.schema, schema);
        expect(state.workflow, releaseWorkflow);
        expect(state.yaml, releaseYaml);
        expect(state.dirty, isFalse);
        expect(state.document, WorkflowDocument.parse(releaseYaml));
        expect(state.command, WorkflowCommand.none);
        verify(() => workflows.validate('prj_1', releaseYaml)).called(1);
        await bloc.close();
      },
    );

    blocTest<WorkflowBuilderBloc, WorkflowBuilderState>(
      'opens the workflow it is given, without a schema if the engine has '
      'none, else the first built-in',
      setUp: () {
        when(workflows.schema)
            .thenThrow(const ConnectionException('Connection refused.'));
      },
      build: build,
      act: (bloc) =>
          bloc.add(const WorkflowBuilderStarted(workflowId: 'wf_dev')),
      wait: const Duration(milliseconds: 10),
      verify: (bloc) {
        expect(bloc.state.workflow, devBuild);
        expect(bloc.state.schema, isNull);
        expect(bloc.state.savesAsNew, isTrue);
      },
    );

    blocTest<WorkflowBuilderBloc, WorkflowBuilderState>(
      'opens the first built-in when the owner has none',
      setUp: () =>
          when(() => workflows.listWorkflows('prj_1'))
              .thenAnswer((_) async => [summaryOf(devBuild)]),
      build: build,
      act: (bloc) => bloc.add(const WorkflowBuilderStarted()),
      wait: const Duration(milliseconds: 10),
      verify: (bloc) => expect(bloc.state.workflow, devBuild),
    );

    blocTest<WorkflowBuilderBloc, WorkflowBuilderState>(
      'starts a draft when the project has no workflow',
      setUp: () =>
          when(() => workflows.listWorkflows('prj_1'))
              .thenAnswer((_) async => []),
      build: build,
      act: (bloc) => bloc.add(const WorkflowBuilderStarted()),
      wait: const Duration(milliseconds: 10),
      verify: (bloc) {
        expect(bloc.state.workflow, isNull);
        expect(bloc.state.document, draftTemplate);
        expect(bloc.state.dirty, isTrue);
      },
    );

    blocTest<WorkflowBuilderBloc, WorkflowBuilderState>(
      'says why the workflows could not be read',
      setUp: () => when(() => workflows.listWorkflows('prj_1'))
          .thenThrow(const ApiException('No such project.', statusCode: 404)),
      build: build,
      act: (bloc) => bloc.add(const WorkflowBuilderStarted()),
      expect: () => const [
        WorkflowBuilderState(command: WorkflowCommand.loading),
        WorkflowBuilderState(loaded: true, error: 'No such project.'),
      ],
    );
  });

  group('opening', () {
    test('another workflow, and says why one could not be read', () async {
      final bloc = await opened();
      when(() => workflows.getWorkflow('prj_1', 'wf_gone')).thenThrow(
        const ApiException('There is no workflow wf_gone.', statusCode: 404),
      );

      bloc.add(const WorkflowOpened('wf_dev'));
      await bloc.stream.firstWhere((s) => s.workflow == devBuild);
      bloc.add(const WorkflowOpened('wf_gone'));
      final failed = await bloc.stream.firstWhere((s) => s.error != null);

      expect(failed.error, 'There is no workflow wf_gone.');
      expect(failed.workflow, devBuild);
      expect(failed.command, WorkflowCommand.none);
      await bloc.close();
    });

    blocTest<WorkflowBuilderBloc, WorkflowBuilderState>(
      'a new workflow from the template',
      build: build,
      act: (bloc) => bloc.add(const WorkflowDraftStarted()),
      wait: const Duration(milliseconds: 10),
      verify: (bloc) {
        expect(bloc.state.yaml, draftTemplate.toYaml());
        expect(bloc.state.document, draftTemplate);
        expect(bloc.state.savesAsNew, isTrue);
        expect(bloc.state.validation, WorkflowValidation.valid);
      },
    );
  });

  group('importing', () {
    blocTest<WorkflowBuilderBloc, WorkflowBuilderState>(
      'opens a picked file as a draft named after it',
      setUp: () => picked = PickedFile(
        name: 'nightly.yaml',
        bytes: utf8.encode(releaseYaml),
      ),
      build: build,
      act: (bloc) => bloc.add(const WorkflowImportRequested()),
      wait: const Duration(milliseconds: 10),
      verify: (bloc) {
        expect(bloc.state.draftName, 'nightly');
        expect(bloc.state.name, 'nightly');
        expect(bloc.state.workflow, isNull);
        expect(bloc.state.yaml, releaseYaml);
        expect(bloc.state.dirty, isTrue);
        expect(bloc.state.document?.name, 'Store release');
      },
    );

    blocTest<WorkflowBuilderBloc, WorkflowBuilderState>(
      'does nothing when the owner cancels',
      build: build,
      act: (bloc) => bloc.add(const WorkflowImportRequested()),
      expect: () => const [
        WorkflowBuilderState(command: WorkflowCommand.importing),
        WorkflowBuilderState(),
      ],
    );

    blocTest<WorkflowBuilderBloc, WorkflowBuilderState>(
      'says why the file could not be read',
      build: () => WorkflowBuilderBloc(
        workflows: workflows,
        projectId: 'prj_1',
        pickFile: () async => throw const FileSystemException('Gone'),
        saveFile: (_, _) async => null,
      ),
      act: (bloc) => bloc.add(const WorkflowImportRequested()),
      expect: () => const [
        WorkflowBuilderState(command: WorkflowCommand.importing),
        WorkflowBuilderState(error: "FileSystemException: Gone, path = ''"),
      ],
    );
  });

  group('exporting', () {
    test('writes the YAML under the name of the workflow', () async {
      final bloc = await opened();

      bloc.add(const WorkflowExportRequested());
      final done = await bloc.stream.firstWhere((s) => s.notice != null);

      expect(saved, [('store-release.yaml', releaseYaml)]);
      expect(
        done.notice,
        const WorkflowExportedNotice('/tmp/store-release.yaml'),
      );
      await bloc.close();
    });

    blocTest<WorkflowBuilderBloc, WorkflowBuilderState>(
      'says nothing when the owner cancels',
      build: () => WorkflowBuilderBloc(
        workflows: workflows,
        projectId: 'prj_1',
        pickFile: () async => null,
        saveFile: (name, _) async {
          saved.add((name, ''));
          return null;
        },
      ),
      act: (bloc) => bloc.add(const WorkflowExportRequested()),
      expect: () => const [
        WorkflowBuilderState(command: WorkflowCommand.exporting),
        WorkflowBuilderState(),
      ],
      verify: (_) => expect(saved, [('workflow.yaml', '')]),
    );

    blocTest<WorkflowBuilderBloc, WorkflowBuilderState>(
      'says why the file could not be written',
      setUp: () => saveError = const FileSystemException('Read-only'),
      build: build,
      act: (bloc) => bloc.add(const WorkflowExportRequested()),
      expect: () => const [
        WorkflowBuilderState(command: WorkflowCommand.exporting),
        WorkflowBuilderState(
          error: "FileSystemException: Read-only, path = ''",
        ),
      ],
    );
  });

  group('editing', () {
    test(
      'round trip: a visual edit writes YAML that parses to the edited model',
      () async {
        final bloc = await opened();
        final edited = bloc.state.document!
            .addStage('ship')
            .editJob(
              1,
              0,
              (job) => job
                  .withAxis(
                    'platform',
                    const WorkflowMatrixAxis.list('platform', [
                      'android',
                      'ios',
                    ]),
                  )
                  .copyWith(
                    condition: () => '!flavor.prod',
                    capabilities: ['flutter', 'ios-sign'],
                  )
                  .addStep('command')
                  .editStep(
                    3,
                    (step) => step.copyWith(
                      condition: () => "platform == 'ios'",
                      gate: () => 'push',
                      withValues: {'run': 'echo one\necho two', 'n': 2},
                    ),
                  ),
            )
            .editStage(0, (stage) => stage.copyWith(name: 'verify'))
            .copyWith(name: () => 'Store: release', locksProject: false);

        bloc.add(
          WorkflowDocumentEdited(
            edited,
            selection: const WorkflowSelection(stage: 2, job: 0),
          ),
        );
        final state = await bloc.stream.firstWhere(
          (s) =>
              s.document == edited && s.validation == WorkflowValidation.valid,
        );

        expect(WorkflowDocument.parse(state.yaml), edited);
        expect(state.yaml, contains('platform: [android, ios]'));
        expect(state.yaml, contains("if: '!flavor.prod'"));
        expect(state.yaml, contains("name: 'Store: release'"));
        expect(state.selection, const WorkflowSelection(stage: 2, job: 0));
        expect(state.dirty, isTrue);
        verify(() => workflows.validate('prj_1', state.yaml)).called(1);
        await bloc.close();
      },
    );

    test('typed YAML updates the model, or keeps it while it cannot', () async {
      final bloc = await opened();
      bloc.add(
        const WorkflowSelectionChanged(WorkflowSelection(stage: 1, job: 0)),
      );
      final good = releaseYaml.replaceFirst('name: build', 'name: compile');

      bloc
        ..add(WorkflowYamlChanged(good))
        ..add(WorkflowYamlChanged(good));
      final read = await bloc.stream.firstWhere((s) => s.yaml == good);
      expect(read.document!.stages[1].name, 'compile');
      expect(read.selection, const WorkflowSelection(stage: 1, job: 0));

      bloc.add(const WorkflowYamlChanged('stages:\n  - oops\n'));
      final broken = await bloc.stream.firstWhere(
        (s) => s.shapeIssues.isNotEmpty,
      );
      expect(broken.editable, isFalse);
      expect(broken.document, read.document);
      expect(broken.shapeIssues.single.line, 2);

      bloc.add(const WorkflowYamlChanged('stages: []\n'));
      final emptied = await bloc.stream.firstWhere(
        (s) => s.shapeIssues.isEmpty,
      );
      expect(emptied.selection, WorkflowSelection.workflow);
      await bloc.close();
    });

    blocTest<WorkflowBuilderBloc, WorkflowBuilderState>(
      'selects within the document, or as asked before there is one',
      build: build,
      seed: () => const WorkflowBuilderState(
        document: WorkflowDocument(stages: [WorkflowStage(name: 's')]),
      ),
      act: (bloc) => bloc.add(
        const WorkflowSelectionChanged(WorkflowSelection(stage: 3, job: 1)),
      ),
      expect: () => const [
        WorkflowBuilderState(
          document: WorkflowDocument(stages: [WorkflowStage(name: 's')]),
          selection: WorkflowSelection(stage: 0),
        ),
      ],
    );

    blocTest<WorkflowBuilderBloc, WorkflowBuilderState>(
      'keeps a selection without a document',
      build: build,
      act: (bloc) =>
          bloc.add(const WorkflowSelectionChanged(WorkflowSelection(stage: 3))),
      expect: () => const [
        WorkflowBuilderState(selection: WorkflowSelection(stage: 3)),
      ],
    );
  });

  group('checking', () {
    test('shows the issues the engine finds, and keeps them when it cannot '
        'check', () async {
      const issue = WorkflowIssue(line: 3, column: 1, message: 'Bad.');
      when(() => workflows.validate('prj_1', 'bad: 1\n')).thenAnswer(
        (_) async =>
            const ValidateWorkflowResponse(valid: false, issues: [issue]),
      );
      when(() => workflows.validate('prj_1', 'away: 1\n'))
          .thenThrow(const ConnectionException('Connection refused.'));
      final bloc = await opened();

      bloc.add(const WorkflowYamlChanged('bad: 1\n'));
      final invalid = await bloc.stream.firstWhere(
        (s) => s.validation == WorkflowValidation.invalid,
      );
      expect(invalid.engineIssues, const [issue]);

      bloc.add(const WorkflowYamlChanged('away: 1\n'));
      final away = await bloc.stream.firstWhere(
        (s) => s.validation == WorkflowValidation.unavailable,
      );
      expect(away.engineIssues, const [issue]);
      expect(away.issues, contains(issue));
      await bloc.close();
    });
  });

  group('saving', () {
    test('a new version of the open workflow', () async {
      const yaml = '$releaseYaml# tuned\n';
      final next = Workflow(
        id: 'wf_mine',
        projectId: 'prj_1',
        name: 'store-release',
        builtin: false,
        version: versionInfo(3),
        versions: [versionInfo(1), versionInfo(2), versionInfo(3)],
        yaml: yaml,
      );
      when(() => workflows.saveWorkflow('prj_1', 'wf_mine', yaml))
          .thenAnswer((_) async => next);
      final bloc = await opened()
        ..add(const WorkflowYamlChanged(yaml));
      await bloc.stream.firstWhere((s) => s.yaml == yaml);

      bloc.add(const WorkflowSaveRequested());
      final done = await bloc.stream.firstWhere((s) => s.notice != null);

      expect(done.workflow, next);
      expect(done.dirty, isFalse);
      expect(done.notice, const WorkflowSavedNotice('store-release', 3));
      expect(done.command, WorkflowCommand.none);
      await bloc.close();
    });

    test('a draft or a built-in only under a new name', () async {
      final copy = Workflow(
        id: 'wf_copy',
        projectId: 'prj_1',
        name: 'my-dev',
        builtin: false,
        version: versionInfo(1),
        versions: [versionInfo(1)],
        yaml: devBuild.yaml,
      );
      when(
        () => workflows.createWorkflow(
          'prj_1',
          name: 'my-dev',
          yaml: devBuild.yaml,
        ),
      ).thenAnswer((_) async => copy);
      final bloc = await opened()
        ..add(const WorkflowOpened('wf_dev'));
      await bloc.stream.firstWhere((s) => s.workflow == devBuild);

      bloc.add(const WorkflowSaveRequested());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      verifyNever(() => workflows.saveWorkflow(any(), any(), any()));

      bloc.add(const WorkflowSaveRequested(name: 'my-dev'));
      final done = await bloc.stream.firstWhere((s) => s.notice != null);
      expect(done.workflow, copy);
      expect(done.savesAsNew, isFalse);
      expect(done.notice, const WorkflowSavedNotice('my-dev', 1));
      await bloc.close();
    });

    test('says why the engine refused', () async {
      when(
        () => workflows.createWorkflow(
          'prj_1',
          name: 'dev-build',
          yaml: any(named: 'yaml'),
        ),
      ).thenThrow(
        const ApiException(
          'The project has a workflow called "dev-build" already.',
          statusCode: 409,
        ),
      );
      final bloc = build()..add(const WorkflowDraftStarted());
      await bloc.stream.firstWhere((s) => s.yaml.isNotEmpty);

      bloc.add(const WorkflowSaveRequested(name: 'dev-build'));
      final failed = await bloc.stream.firstWhere((s) => s.error != null);

      expect(failed.error, contains('already'));
      expect(failed.command, WorkflowCommand.none);
      expect(failed.dirty, isTrue);
      await bloc.close();
    });
  });
}

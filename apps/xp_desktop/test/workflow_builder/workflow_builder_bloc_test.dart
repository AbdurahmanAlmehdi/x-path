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

  setUpAll(() => registerFallbackValue(const UpdateWorkflowRequest()));

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
    expect(const WorkflowDraftStarted().props, [null]);
    expect(const WorkflowUndoRequested().props, isEmpty);
    expect(const WorkflowRenameRequested('n').props, ['n']);
    expect(const WorkflowArchiveRequested(archived: true).props, [true]);
    expect(const WorkflowDeleteRequested().props, isEmpty);
    expect(const WorkflowVersionsCompared(1, 2).props, [1, 2]);
    expect(const WorkflowVersionRestored(1).props, [1]);
    expect(const WorkflowBuiltinCompared().props, isEmpty);
    expect(const WorkflowCaughtUp().props, isEmpty);
    expect(const WorkflowDeletedNotice('n').props, ['n']);
    expect(const WorkflowRestoredNotice('n', 1, 2).props, ['n', 1, 2]);
    expect(const WorkflowRedoRequested().props, isEmpty);
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

  group('templates', () {
    test(
      'reads them at the start, and none while the engine is away',
      () async {
        final bloc = await opened();
        expect(bloc.state.templates, templates);
        await bloc.close();

        when(workflows.templates).thenThrow(const ConnectionException('away'));
        final away = await opened();
        expect(away.state.templates, isEmpty);
        await away.close();
      },
    );

    blocTest<WorkflowBuilderBloc, WorkflowBuilderState>(
      'starts a draft from a template, named after it',
      build: build,
      act: (bloc) => bloc
        ..add(WorkflowDraftStarted(template: templates.last))
        ..add(WorkflowDraftStarted(template: templates.first)),
      wait: const Duration(milliseconds: 10),
      verify: (bloc) {
        expect(bloc.state.yaml, templates.first.yaml);
        expect(bloc.state.draftName, isNull, reason: 'blank has no name');
        expect(bloc.state.workflow, isNull);
      },
    );

    blocTest<WorkflowBuilderBloc, WorkflowBuilderState>(
      'a template other than blank names the draft',
      build: build,
      act: (bloc) => bloc.add(WorkflowDraftStarted(template: templates.last)),
      wait: const Duration(milliseconds: 10),
      verify: (bloc) {
        expect(bloc.state.yaml, templates.last.yaml);
        expect(bloc.state.draftName, 'tests');
      },
    );
  });

  group('undo', () {
    test(
      'removing a step and undoing it gives the YAML back exactly',
      () async {
        final bloc = await opened();
        final document = bloc.state.document!;

        bloc.add(
          WorkflowDocumentEdited(
            document.editJob(1, 0, (j) => j.removeStep(0)),
          ),
        );
        await bloc.stream.firstWhere((s) => s.yaml != releaseYaml);
        expect(bloc.state.canUndo, isTrue);
        expect(bloc.state.canRedo, isFalse);

        bloc.add(const WorkflowUndoRequested());
        await bloc.stream.firstWhere((s) => s.yaml == releaseYaml);
        expect(bloc.state.document, document);
        expect(bloc.state.canUndo, isFalse);
        expect(bloc.state.canRedo, isTrue);
        expect(bloc.state.dirty, isFalse);

        bloc.add(const WorkflowRedoRequested());
        await bloc.stream.firstWhere((s) => s.yaml != releaseYaml);
        expect(bloc.state.document!.stages[1].jobs.single.steps, hasLength(2));
        expect(bloc.state.canRedo, isFalse);
        await bloc.close();
      },
    );

    test('nothing to undo or redo does nothing', () async {
      final bloc = await opened();
      final before = bloc.state;

      bloc
        ..add(const WorkflowUndoRequested())
        ..add(const WorkflowRedoRequested());
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(bloc.state, before);
      await bloc.close();
    });

    test('typing in a row is one step, a structural edit its own', () async {
      var now = DateTime(2026, 10, 24, 9);
      final bloc = WorkflowBuilderBloc(
        workflows: workflows,
        projectId: 'prj_1',
        pickFile: () async => null,
        saveFile: (_, _) async => null,
        debounce: Duration.zero,
        now: () => now,
      )..add(const WorkflowBuilderStarted());
      await bloc.stream.firstWhere((s) => s.yaml == releaseYaml);

      bloc
        ..add(const WorkflowYamlChanged('${releaseYaml}a'))
        ..add(const WorkflowYamlChanged('${releaseYaml}ab'));
      await bloc.stream.firstWhere((s) => s.yaml == '${releaseYaml}ab');
      expect(bloc.state.undoStack, [releaseYaml]);

      now = now.add(const Duration(seconds: 2));
      bloc.add(const WorkflowYamlChanged(releaseYaml));
      await bloc.stream.firstWhere((s) => s.yaml == releaseYaml);
      expect(bloc.state.undoStack, [releaseYaml, '${releaseYaml}ab']);

      final document = bloc.state.document!;
      bloc
        ..add(WorkflowDocumentEdited(document.copyWith(name: () => 'S')))
        ..add(WorkflowDocumentEdited(document.copyWith(name: () => 'Sh')));
      await bloc.stream.firstWhere((s) => s.document?.name == 'Sh');
      expect(bloc.state.undoStack, hasLength(3));

      bloc.add(WorkflowDocumentEdited(bloc.state.document!.addStage('more')));
      await bloc.stream.firstWhere((s) => s.document!.stages.length == 3);
      expect(bloc.state.undoStack, hasLength(4));

      bloc.add(WorkflowDocumentEdited(bloc.state.document!));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(bloc.state.undoStack, hasLength(4), reason: 'no change');
      await bloc.close();
    });

    test('keeps the last steps only, and forgets them on open', () async {
      final bloc = await opened();

      for (var i = 0; i <= WorkflowBuilderBloc.undoLimit; i++) {
        bloc.add(WorkflowDocumentEdited(bloc.state.document!.addStage('s$i')));
        await bloc.stream.firstWhere(
          (s) => s.document!.stages.any((stage) => stage.name == 's$i'),
        );
      }
      expect(bloc.state.undoStack, hasLength(WorkflowBuilderBloc.undoLimit));

      bloc.add(const WorkflowOpened('wf_dev'));
      await bloc.stream.firstWhere((s) => s.workflow == devBuild);
      expect(bloc.state.undoStack, isEmpty);
      expect(bloc.state.redoStack, isEmpty);
      await bloc.close();
    });
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
        WorkflowBuilderState(error: 'Gone'),
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
        WorkflowBuilderState(error: 'Read-only'),
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

  group('lifecycle (UX-06)', () {
    Workflow mine({DateTime? archivedAt, WorkflowBasedOn? basedOn}) => Workflow(
      id: 'wf_mine',
      projectId: 'prj_1',
      name: 'store-release',
      builtin: false,
      version: releaseWorkflow.version,
      versions: releaseWorkflow.versions,
      yaml: releaseYaml,
      archivedAt: archivedAt,
      basedOn: basedOn,
    );

    test('renames and archives the open workflow', () async {
      final archived = mine(archivedAt: DateTime.utc(2026));
      when(
        () => workflows.updateWorkflow(
          'prj_1',
          'wf_mine',
          const UpdateWorkflowRequest(archived: true),
        ),
      ).thenAnswer((_) async => archived);
      final bloc = await opened();

      bloc.add(const WorkflowArchiveRequested(archived: true));
      final done = await bloc.stream.firstWhere((s) => s.workflow == archived);

      expect(done.command, WorkflowCommand.none);
      verify(() => workflows.listWorkflows('prj_1')).called(2);

      when(
        () => workflows.updateWorkflow(
          'prj_1',
          'wf_mine',
          const UpdateWorkflowRequest(name: 'nightly'),
        ),
      ).thenThrow(const ApiException('Taken.', statusCode: 409));
      bloc.add(const WorkflowRenameRequested('nightly'));
      final failed = await bloc.stream.firstWhere((s) => s.error != null);
      expect(failed.error, 'Taken.');
      expect(failed.command, WorkflowCommand.none);
      await bloc.close();
    });

    test('changes no built-in', () async {
      final bloc = await opened()
        ..add(const WorkflowOpened('wf_dev'));
      await bloc.stream.firstWhere((s) => s.workflow == devBuild);

      bloc
        ..add(const WorkflowRenameRequested('x'))
        ..add(const WorkflowDeleteRequested())
        ..add(const WorkflowVersionRestored(1));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      verifyNever(() => workflows.updateWorkflow(any(), any(), any()));
      verifyNever(() => workflows.deleteWorkflow(any(), any()));
      verifyNever(() => workflows.saveWorkflow(any(), any(), any()));
      await bloc.close();
    });

    test('deletes the open workflow and opens the next', () async {
      when(() => workflows.deleteWorkflow('prj_1', 'wf_mine'))
          .thenAnswer((_) async {});
      final bloc = await opened();
      when(() => workflows.listWorkflows('prj_1'))
          .thenAnswer((_) async => [summaryOf(devBuild)]);

      bloc.add(const WorkflowDeleteRequested());
      final done = await bloc.stream.firstWhere(
        (s) => s.notice is WorkflowDeletedNotice,
      );

      expect(done.workflow, devBuild);
      expect(done.notice, const WorkflowDeletedNotice('store-release'));
      await bloc.close();
    });

    test('starts a draft when the last workflow is deleted', () async {
      when(() => workflows.deleteWorkflow('prj_1', 'wf_mine'))
          .thenAnswer((_) async {});
      final bloc = await opened();
      when(() => workflows.listWorkflows('prj_1')).thenAnswer((_) async => []);

      bloc.add(const WorkflowDeleteRequested());
      final done = await bloc.stream.firstWhere(
        (s) => s.notice is WorkflowDeletedNotice,
      );

      expect(done.workflow, isNull);
      expect(done.document, draftTemplate);
      await bloc.close();
    });

    test('compares two versions, and says why it could not', () async {
      when(() => workflows.getWorkflow('prj_1', 'wf_mine', version: 1))
          .thenAnswer((_) async => mine());
      when(() => workflows.getWorkflow('prj_1', 'wf_mine', version: 2))
          .thenAnswer((_) async => releaseWorkflow);
      final bloc = await opened();

      bloc.add(const WorkflowVersionsCompared(1, 2));
      final diff = await bloc.stream.firstWhere((s) => s.versionDiff != null);
      expect(
        diff.versionDiff,
        const VersionDiff(
          from: 1,
          to: 2,
          before: releaseYaml,
          after: releaseYaml,
        ),
      );

      when(() => workflows.getWorkflow('prj_1', 'wf_mine', version: 1))
          .thenThrow(const ApiException('Gone.', statusCode: 404));
      bloc.add(const WorkflowVersionsCompared(1, 2));
      final failed = await bloc.stream.firstWhere((s) => s.error != null);
      expect(failed.error, 'Gone.');
      expect(failed.versionDiff, isNull);
      await bloc.close();
    });

    test('saves an older version again as the newest', () async {
      const old = '$releaseYaml# first\n';
      final restored = Workflow(
        id: 'wf_mine',
        projectId: 'prj_1',
        name: 'store-release',
        builtin: false,
        version: versionInfo(3),
        versions: [versionInfo(1), versionInfo(2), versionInfo(3)],
        yaml: old,
      );
      when(() => workflows.getWorkflow('prj_1', 'wf_mine', version: 1))
          .thenAnswer(
            (_) async => Workflow(
              id: 'wf_mine',
              projectId: 'prj_1',
              name: 'store-release',
              builtin: false,
              version: versionInfo(1),
              versions: releaseWorkflow.versions,
              yaml: old,
            ),
          );
      when(() => workflows.saveWorkflow('prj_1', 'wf_mine', old))
          .thenAnswer((_) async => restored);
      final bloc = await opened();

      bloc.add(const WorkflowVersionRestored(1));
      final done = await bloc.stream.firstWhere(
        (s) => s.notice is WorkflowRestoredNotice,
      );

      expect(done.yaml, old);
      expect(done.dirty, isFalse);
      expect(done.workflow, restored);
      expect(done.notice, const WorkflowRestoredNotice('store-release', 1, 3));
      expect(done.undoStack, [releaseYaml]);
      await bloc.close();
    });

    test('compares a copy with its built-in and catches it up', () async {
      const basedOn = WorkflowBasedOn(builtin: 'dev-build', version: 1);
      final newer = WorkflowSummary(
        id: 'wf_dev',
        projectId: 'prj_1',
        name: 'dev-build',
        builtin: true,
        version: versionInfo(2),
      );
      when(() => workflows.listWorkflows('prj_1'))
          .thenAnswer((_) async => [newer, summaryOf(mine(basedOn: basedOn))]);
      when(() => workflows.getWorkflow('prj_1', 'wf_mine'))
          .thenAnswer((_) async => mine(basedOn: basedOn));
      when(() => workflows.getWorkflow('prj_1', 'wf_dev', version: 1))
          .thenAnswer((_) async => devBuild);
      when(() => workflows.getWorkflow('prj_1', 'wf_dev')).thenAnswer(
        (_) async => Workflow(
          id: 'wf_dev',
          projectId: 'prj_1',
          name: 'dev-build',
          builtin: true,
          version: versionInfo(2),
          versions: [versionInfo(1), versionInfo(2)],
          yaml: '${devBuild.yaml}# 2\n',
        ),
      );
      const caught = WorkflowBasedOn(builtin: 'dev-build', version: 2);
      when(
        () => workflows.updateWorkflow(
          'prj_1',
          'wf_mine',
          const UpdateWorkflowRequest(basedOnVersion: 2),
        ),
      ).thenAnswer((_) async => mine(basedOn: caught));
      final bloc = await opened();
      expect(bloc.state.builtinUpdate, (
        builtin: 'dev-build',
        base: 1,
        latest: 2,
      ));

      bloc.add(const WorkflowBuiltinCompared());
      final compare = await bloc.stream.firstWhere(
        (s) => s.builtinCompare != null,
      );
      expect(
        compare.builtinCompare,
        BuiltinCompare(
          builtin: 'dev-build',
          base: 1,
          latest: 2,
          baseYaml: devBuild.yaml,
          latestYaml: '${devBuild.yaml}# 2\n',
        ),
      );

      when(() => workflows.listWorkflows('prj_1'))
          .thenAnswer((_) async => [newer, summaryOf(mine(basedOn: caught))]);
      bloc.add(const WorkflowCaughtUp());
      final done = await bloc.stream.firstWhere(
        (s) => s.workflow?.basedOn == caught && s.builtinCompare == null,
      );
      expect(done.builtinUpdate, isNull);
      await bloc.close();
    });

    test('has nothing to compare without a newer built-in', () async {
      final bloc = await opened();

      expect(bloc.state.builtinUpdate, isNull);
      bloc
        ..add(const WorkflowBuiltinCompared())
        ..add(const WorkflowCaughtUp());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(bloc.state.builtinCompare, isNull);
      verifyNever(() => workflows.updateWorkflow(any(), any(), any()));
      await bloc.close();
    });

    test('says why the built-in could not be read', () async {
      const basedOn = WorkflowBasedOn(builtin: 'dev-build', version: 1);
      when(() => workflows.listWorkflows('prj_1')).thenAnswer(
        (_) async => [
          WorkflowSummary(
            id: 'wf_dev',
            projectId: 'prj_1',
            name: 'dev-build',
            builtin: true,
            version: versionInfo(2),
          ),
          summaryOf(mine(basedOn: basedOn)),
        ],
      );
      when(() => workflows.getWorkflow('prj_1', 'wf_mine'))
          .thenAnswer((_) async => mine(basedOn: basedOn));
      when(() => workflows.getWorkflow('prj_1', 'wf_dev', version: 1))
          .thenThrow(const ApiException('Gone.', statusCode: 404));
      final bloc = await opened();

      bloc.add(const WorkflowBuiltinCompared());
      final failed = await bloc.stream.firstWhere((s) => s.error != null);

      expect(failed.error, 'Gone.');
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
          basedOn: const WorkflowBasedOn(builtin: 'dev-build', version: 1),
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

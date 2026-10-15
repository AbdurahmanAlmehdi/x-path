import 'dart:convert';

import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:path/path.dart' as p;
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/app/app_services.dart';
import 'package:xp_desktop/workflow_builder/bloc/workflow_edits.dart';
import 'package:xp_repositories/xp_repositories.dart';

sealed class WorkflowBuilderEvent extends Equatable {
  const new();

  @override
  List<Object?> get props => [];
}

/// Reads the workflows of the project and the engine's schema, and opens
/// [workflowId] (else the first workflow).
final class WorkflowBuilderStarted extends WorkflowBuilderEvent {
  const new({this.workflowId});

  final String? workflowId;

  @override
  List<Object?> get props => [workflowId];
}

/// Opens the newest version of [workflowId].
final class WorkflowOpened extends WorkflowBuilderEvent {
  const new(this.workflowId);

  final String workflowId;

  @override
  List<Object?> get props => [workflowId];
}

/// Starts a new, unsaved workflow from a small template.
final class WorkflowDraftStarted extends WorkflowBuilderEvent {
  const new();
}

/// Asks for a YAML file and opens it as a new, unsaved workflow.
final class WorkflowImportRequested extends WorkflowBuilderEvent {
  const new();
}

/// Asks where to save the YAML of the open workflow and writes it there.
final class WorkflowExportRequested extends WorkflowBuilderEvent {
  const new();
}

/// The owner typed in the YAML view.
final class WorkflowYamlChanged extends WorkflowBuilderEvent {
  const new(this.yaml);

  final String yaml;

  @override
  List<Object?> get props => [yaml];
}

/// The owner changed the document in the visual editor.
final class WorkflowDocumentEdited extends WorkflowBuilderEvent {
  const new(this.document, {this.selection});

  final WorkflowDocument document;

  /// What to show in the inspector after the edit; the current selection
  /// by default.
  final WorkflowSelection? selection;

  @override
  List<Object?> get props => [document, selection];
}

/// Shows [selection] in the inspector.
final class WorkflowSelectionChanged extends WorkflowBuilderEvent {
  const new(this.selection);

  final WorkflowSelection selection;

  @override
  List<Object?> get props => [selection];
}

/// Saves the YAML: a new version of the open workflow, or, with [name], a
/// new workflow (a draft, an import, or a copy of a built-in).
final class WorkflowSaveRequested extends WorkflowBuilderEvent {
  const new({this.name});

  final String? name;

  @override
  List<Object?> get props => [name];
}

final class _WorkflowValidationRequested extends WorkflowBuilderEvent {
  const new();
}

/// What the engine said of the YAML.
enum WorkflowValidation {
  /// Nothing asked yet.
  idle,

  /// Waiting for the engine.
  checking,

  /// The engine found no issue.
  valid,

  /// The engine found issues.
  invalid,

  /// The engine could not be asked (it is away).
  unavailable,
}

/// What the builder is sending or reading.
enum WorkflowCommand { none, loading, saving, importing, exporting }

/// Something that went well, said once.
sealed class WorkflowNotice extends Equatable {
  const new();
}

/// The workflow was saved as [version] of [name].
final class WorkflowSavedNotice extends WorkflowNotice {
  const new(this.name, this.version);

  final String name;
  final int version;

  @override
  List<Object?> get props => [name, version];
}

/// The YAML was written to [path].
final class WorkflowExportedNotice extends WorkflowNotice {
  const new(this.path);

  final String path;

  @override
  List<Object?> get props => [path];
}

class WorkflowBuilderState extends Equatable {
  const new({
    this.loaded = false,
    this.workflows = const [],
    this.schema,
    this.workflow,
    this.draftName,
    this.yaml = '',
    this.savedYaml = '',
    this.document,
    this.shapeIssues = const [],
    this.engineIssues = const [],
    this.validation = WorkflowValidation.idle,
    this.selection = WorkflowSelection.workflow,
    this.command = WorkflowCommand.none,
    this.notice,
    this.error,
  });

  /// Whether the list of workflows arrived.
  final bool loaded;

  /// The workflows of the project.
  final List<WorkflowSummary> workflows;

  /// What a document may name, for the pickers; `null` until the engine
  /// answers.
  final WorkflowSchema? schema;

  /// The saved workflow the builder edits; `null` for a draft.
  final Workflow? workflow;

  /// The name a draft is offered when it is saved (an imported file's).
  final String? draftName;

  /// The YAML being edited: what is saved and what the engine checks.
  final String yaml;

  /// The YAML as last saved (empty for a draft).
  final String savedYaml;

  /// [yaml] read into the model; the last good reading while [shapeIssues]
  /// says the YAML cannot be read.
  final WorkflowDocument? document;

  /// What keeps [yaml] from being read into the model, with lines. The
  /// visual editor waits while there are any.
  final List<WorkflowIssue> shapeIssues;

  /// The issues the engine found in [yaml], with lines.
  final List<WorkflowIssue> engineIssues;

  final WorkflowValidation validation;
  final WorkflowSelection selection;
  final WorkflowCommand command;
  final WorkflowNotice? notice;
  final String? error;

  /// Whether [yaml] differs from what is saved.
  bool get dirty => yaml != savedYaml;

  /// Whether saving makes a new workflow (and so needs a name).
  bool get savesAsNew => workflow == null || workflow!.builtin;

  /// Whether the visual editor can edit (the YAML reads as a workflow).
  bool get editable => document != null && shapeIssues.isEmpty;

  /// Every issue, local and the engine's, once each, by place.
  List<WorkflowIssue> get issues => {...shapeIssues, ...engineIssues}.toList()
    ..sort(
      (a, b) => a.line != b.line
          ? a.line.compareTo(b.line)
          : a.column.compareTo(b.column),
    );

  /// What the open workflow is called: its name, the draft's, or `null`.
  String? get name => workflow?.name ?? draftName;

  WorkflowBuilderState copyWith({
    bool? loaded,
    List<WorkflowSummary>? workflows,
    WorkflowSchema? schema,
    Workflow? Function()? workflow,
    String? Function()? draftName,
    String? yaml,
    String? savedYaml,
    WorkflowDocument? Function()? document,
    List<WorkflowIssue>? shapeIssues,
    List<WorkflowIssue>? engineIssues,
    WorkflowValidation? validation,
    WorkflowSelection? selection,
    WorkflowCommand? command,
    WorkflowNotice? Function()? notice,
    String? Function()? error,
  }) => WorkflowBuilderState(
    loaded: loaded ?? this.loaded,
    workflows: workflows ?? this.workflows,
    schema: schema ?? this.schema,
    workflow: workflow == null ? this.workflow : workflow(),
    draftName: draftName == null ? this.draftName : draftName(),
    yaml: yaml ?? this.yaml,
    savedYaml: savedYaml ?? this.savedYaml,
    document: document == null ? this.document : document(),
    shapeIssues: shapeIssues ?? this.shapeIssues,
    engineIssues: engineIssues ?? this.engineIssues,
    validation: validation ?? this.validation,
    selection: selection ?? this.selection,
    command: command ?? this.command,
    notice: notice == null ? this.notice : notice(),
    error: error == null ? this.error : error(),
  );

  @override
  List<Object?> get props => [
    loaded,
    workflows,
    schema,
    workflow,
    draftName,
    yaml,
    savedYaml,
    document,
    shapeIssues,
    engineIssues,
    validation,
    selection,
    command,
    notice,
    error,
  ];
}

/// The document a new workflow starts from: one stage, one job, one step.
const draftTemplate = WorkflowDocument(
  name: 'New workflow',
  stages: [
    WorkflowStage(
      name: 'build',
      jobs: [
        WorkflowJob(
          id: 'build',
          steps: [WorkflowStep(kind: 'git.checkout')],
        ),
      ],
    ),
  ],
);

/// The workflow builder of one project (PRODUCT §6.9): the visual editor and
/// the YAML view edit one document; the engine checks it as it changes, with
/// lines; save, import and export.
///
/// The YAML is what is saved: a visual edit writes the model back as YAML,
/// and typing in the YAML reads it into the model when it can.
class WorkflowBuilderBloc
    extends Bloc<WorkflowBuilderEvent, WorkflowBuilderState> {
  new({
    required this._workflows,
    required this._projectId,
    required this._pickFile,
    required this._saveFile,
    this._debounce = const Duration(milliseconds: 400),
  }) : super(const WorkflowBuilderState()) {
    on<WorkflowBuilderStarted>(_onStarted, transformer: restartable());
    on<WorkflowOpened>(_onOpened, transformer: restartable());
    on<WorkflowDraftStarted>(_onDraft);
    on<WorkflowImportRequested>(_onImport, transformer: droppable());
    on<WorkflowExportRequested>(_onExport, transformer: droppable());
    on<WorkflowYamlChanged>(_onYaml);
    on<WorkflowDocumentEdited>(_onEdited);
    on<WorkflowSelectionChanged>(
      (event, emit) => emit(
        state.copyWith(
          selection: state.document == null
              ? event.selection
              : event.selection.within(state.document!),
        ),
      ),
    );
    on<WorkflowSaveRequested>(_onSave, transformer: droppable());
    on<_WorkflowValidationRequested>(_onValidate, transformer: restartable());
  }

  final WorkflowsRepository _workflows;
  final String _projectId;
  final FilePicker _pickFile;
  final FileSaver _saveFile;

  /// How long the YAML must stay still before the engine checks it.
  final Duration _debounce;

  Future<void> _onStarted(
    WorkflowBuilderStarted event,
    Emitter<WorkflowBuilderState> emit,
  ) async {
    emit(state.copyWith(command: WorkflowCommand.loading, error: () => null));
    try {
      final workflows = await _workflows.listWorkflows(_projectId);
      emit(state.copyWith(loaded: true, workflows: workflows));
      final schema = await _schema();
      if (schema != null) emit(state.copyWith(schema: schema));
      final first =
          event.workflowId ??
          workflows.where((w) => !w.builtin).firstOrNull?.id ??
          workflows.firstOrNull?.id;
      if (first == null) {
        emit(state.copyWith(command: WorkflowCommand.none));
        _draft(emit, draftTemplate.toYaml());
        return;
      }
      await _open(first, emit);
    } on Exception catch (error) {
      emit(
        state.copyWith(
          loaded: true,
          command: WorkflowCommand.none,
          error: () => errorMessage(error),
        ),
      );
    }
  }

  /// The schema, or `null` while the engine cannot give it; the builder
  /// then takes step types as text.
  Future<WorkflowSchema?> _schema() async {
    try {
      return await _workflows.schema();
    } on Exception {
      return null;
    }
  }

  Future<void> _onOpened(
    WorkflowOpened event,
    Emitter<WorkflowBuilderState> emit,
  ) async {
    emit(
      state.copyWith(
        command: WorkflowCommand.loading,
        notice: () => null,
        error: () => null,
      ),
    );
    try {
      await _open(event.workflowId, emit);
    } on Exception catch (error) {
      emit(
        state.copyWith(
          command: WorkflowCommand.none,
          error: () => errorMessage(error),
        ),
      );
    }
  }

  Future<void> _open(String id, Emitter<WorkflowBuilderState> emit) async {
    final workflow = await _workflows.getWorkflow(_projectId, id);
    emit(
      _read(
        state.copyWith(
          workflow: () => workflow,
          draftName: () => null,
          savedYaml: workflow.yaml,
          command: WorkflowCommand.none,
          selection: WorkflowSelection.workflow,
        ),
        workflow.yaml,
      ),
    );
    add(const _WorkflowValidationRequested());
  }

  void _onDraft(
    WorkflowDraftStarted event,
    Emitter<WorkflowBuilderState> emit,
  ) => _draft(emit, draftTemplate.toYaml());

  void _draft(Emitter<WorkflowBuilderState> emit, String yaml, {String? name}) {
    emit(
      _read(
        state.copyWith(
          workflow: () => null,
          draftName: () => name,
          savedYaml: '',
          selection: WorkflowSelection.workflow,
          notice: () => null,
          error: () => null,
        ),
        yaml,
      ),
    );
    add(const _WorkflowValidationRequested());
  }

  Future<void> _onImport(
    WorkflowImportRequested event,
    Emitter<WorkflowBuilderState> emit,
  ) async {
    emit(state.copyWith(command: WorkflowCommand.importing));
    try {
      final file = await _pickFile();
      emit(state.copyWith(command: WorkflowCommand.none));
      if (file == null) return;
      _draft(
        emit,
        utf8.decode(file.bytes, allowMalformed: true),
        name: p.basenameWithoutExtension(file.name),
      );
    } on Exception catch (error) {
      emit(
        state.copyWith(
          command: WorkflowCommand.none,
          error: () => errorMessage(error),
        ),
      );
    }
  }

  Future<void> _onExport(
    WorkflowExportRequested event,
    Emitter<WorkflowBuilderState> emit,
  ) async {
    emit(
      state.copyWith(
        command: WorkflowCommand.exporting,
        notice: () => null,
        error: () => null,
      ),
    );
    try {
      final path = await _saveFile(
        '${state.name ?? 'workflow'}.yaml',
        state.yaml,
      );
      emit(
        state.copyWith(
          command: WorkflowCommand.none,
          notice: () => path == null ? null : WorkflowExportedNotice(path),
        ),
      );
    } on Exception catch (error) {
      emit(
        state.copyWith(
          command: WorkflowCommand.none,
          error: () => errorMessage(error),
        ),
      );
    }
  }

  void _onYaml(WorkflowYamlChanged event, Emitter<WorkflowBuilderState> emit) {
    if (event.yaml == state.yaml) return;
    emit(_read(state.copyWith(notice: () => null), event.yaml));
    add(const _WorkflowValidationRequested());
  }

  void _onEdited(
    WorkflowDocumentEdited event,
    Emitter<WorkflowBuilderState> emit,
  ) {
    final document = event.document;
    emit(
      state.copyWith(
        yaml: document.toYaml(),
        document: () => document,
        shapeIssues: const [],
        validation: WorkflowValidation.checking,
        selection: (event.selection ?? state.selection).within(document),
        notice: () => null,
      ),
    );
    add(const _WorkflowValidationRequested());
  }

  /// [state] with [yaml], read into the model if it can be, and waiting
  /// for the engine's check.
  WorkflowBuilderState _read(WorkflowBuilderState state, String yaml) {
    final checking = state.copyWith(
      yaml: yaml,
      validation: WorkflowValidation.checking,
    );
    try {
      final document = WorkflowDocument.parse(yaml);
      return checking.copyWith(
        document: () => document,
        shapeIssues: const [],
        selection: state.selection.within(document),
      );
    } on WorkflowDocumentException catch (error) {
      return checking.copyWith(shapeIssues: error.issues);
    }
  }

  Future<void> _onValidate(
    _WorkflowValidationRequested event,
    Emitter<WorkflowBuilderState> emit,
  ) async {
    emit(state.copyWith(validation: WorkflowValidation.checking));
    await Future<void>.delayed(_debounce);
    final yaml = state.yaml;
    try {
      final result = await _workflows.validate(_projectId, yaml);
      emit(
        state.copyWith(
          engineIssues: result.issues,
          validation: result.valid
              ? WorkflowValidation.valid
              : WorkflowValidation.invalid,
        ),
      );
    } on Exception {
      emit(
        state.copyWith(
          engineIssues: const [],
          validation: WorkflowValidation.unavailable,
        ),
      );
    }
  }

  Future<void> _onSave(
    WorkflowSaveRequested event,
    Emitter<WorkflowBuilderState> emit,
  ) async {
    final name = event.name;
    final workflow = state.workflow;
    if (name == null && state.savesAsNew) return;
    final yaml = state.yaml;
    emit(
      state.copyWith(
        command: WorkflowCommand.saving,
        notice: () => null,
        error: () => null,
      ),
    );
    try {
      final saved = name == null
          ? await _workflows.saveWorkflow(_projectId, workflow!.id, yaml)
          : await _workflows.createWorkflow(_projectId, name: name, yaml: yaml);
      final workflows = await _workflows.listWorkflows(_projectId);
      emit(
        state.copyWith(
          workflows: workflows,
          workflow: () => saved,
          draftName: () => null,
          savedYaml: saved.yaml,
          command: WorkflowCommand.none,
          notice: () => WorkflowSavedNotice(saved.name, saved.version.version),
        ),
      );
    } on Exception catch (error) {
      emit(
        state.copyWith(
          command: WorkflowCommand.none,
          error: () => errorMessage(error),
        ),
      );
    }
  }
}

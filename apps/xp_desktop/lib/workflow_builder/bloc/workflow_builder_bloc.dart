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

/// Starts a new, unsaved workflow from [template], or from a blank one.
final class WorkflowDraftStarted extends WorkflowBuilderEvent {
  const new({this.template});

  final WorkflowTemplate? template;

  @override
  List<Object?> get props => [template];
}

/// Goes back to the YAML before the last change (⌘Z).
final class WorkflowUndoRequested extends WorkflowBuilderEvent {
  const new();
}

/// Puts [yaml] back: the document as it was before a removal, which the
/// removal's Undo restores whatever came after it. It is a change of its
/// own, so ⌘Z takes it back.
final class WorkflowRestored extends WorkflowBuilderEvent {
  const new(this.yaml);

  final String yaml;

  @override
  List<Object?> get props => [yaml];
}

/// Makes the change undone last again (⇧⌘Z).
final class WorkflowRedoRequested extends WorkflowBuilderEvent {
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

/// Renames the open workflow of the owner.
final class WorkflowRenameRequested extends WorkflowBuilderEvent {
  const new(this.name);

  final String name;

  @override
  List<Object?> get props => [name];
}

/// Archives the open workflow of the owner, or unarchives it.
final class WorkflowArchiveRequested extends WorkflowBuilderEvent {
  const new({required this.archived, this.workflowId});

  final bool archived;

  /// The workflow to archive or unarchive: the open one when `null`. An
  /// undo names the one it undoes, which may no longer be open.
  final String? workflowId;

  @override
  List<Object?> get props => [archived, workflowId];
}

/// Deletes the open workflow of the owner; the engine refuses one that ran.
final class WorkflowDeleteRequested extends WorkflowBuilderEvent {
  const new();
}

/// Reads versions [from] and [to] of the open workflow, to compare them.
final class WorkflowVersionsCompared extends WorkflowBuilderEvent {
  const new(this.from, this.to);

  final int from;
  final int to;

  @override
  List<Object?> get props => [from, to];
}

/// Saves version [version] of the open workflow again, as its newest.
final class WorkflowVersionRestored extends WorkflowBuilderEvent {
  const new(this.version);

  final int version;

  @override
  List<Object?> get props => [version];
}

/// Reads the built-in the open copy is based on, then and now, to compare.
final class WorkflowBuiltinCompared extends WorkflowBuilderEvent {
  const new();
}

/// Marks the open copy as caught up with the newest version of its
/// built-in.
final class WorkflowCaughtUp extends WorkflowBuilderEvent {
  const new();
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

/// The workflow [name] was deleted.
final class WorkflowDeletedNotice extends WorkflowNotice {
  const new(this.name);

  final String name;

  @override
  List<Object?> get props => [name];
}

/// Version [from] was saved again as [version] of [name].
final class WorkflowRestoredNotice extends WorkflowNotice {
  const new(this.name, this.from, this.version);

  final String name;
  final int from;
  final int version;

  @override
  List<Object?> get props => [name, from, version];
}

/// Two versions of the open workflow, to compare: [before] is version
/// [from], [after] version [to].
class VersionDiff extends Equatable {
  const new({
    required this.from,
    required this.to,
    required this.before,
    required this.after,
  });

  final int from;
  final int to;
  final String before;
  final String after;

  @override
  List<Object?> get props => [from, to, before, after];
}

/// The built-in an open copy is based on, at the version the copy started
/// from ([base]) and at its newest ([latest]): a three-way compare with the
/// copy's own YAML.
class BuiltinCompare extends Equatable {
  const new({
    required this.builtin,
    required this.base,
    required this.latest,
    required this.baseYaml,
    required this.latestYaml,
  });

  final String builtin;
  final int base;
  final int latest;
  final String baseYaml;
  final String latestYaml;

  @override
  List<Object?> get props => [builtin, base, latest, baseYaml, latestYaml];
}

class WorkflowBuilderState extends Equatable {
  const new({
    this.loaded = false,
    this.workflows = const [],
    this.schema,
    this.templates = const [],
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
    this.undoStack = const [],
    this.redoStack = const [],
    this.versionDiff,
    this.builtinCompare,
  });

  /// Whether the list of workflows arrived.
  final bool loaded;

  /// The workflows of the project.
  final List<WorkflowSummary> workflows;

  /// What a document may name, for the pickers; `null` until the engine
  /// answers.
  final WorkflowSchema? schema;

  /// The documents a new workflow can start from; empty while the engine
  /// cannot give them (a blank one then).
  final List<WorkflowTemplate> templates;

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

  /// The YAML before each change, the last one last: what ⌘Z goes back to.
  final List<String> undoStack;

  /// The YAML of each change undone, the last one last: what ⇧⌘Z redoes.
  final List<String> redoStack;

  bool get canUndo => undoStack.isNotEmpty;
  bool get canRedo => redoStack.isNotEmpty;

  /// The two versions being compared, once read.
  final VersionDiff? versionDiff;

  /// The built-in of the open copy then and now, once read.
  final BuiltinCompare? builtinCompare;

  /// When the open workflow is a copy of a built-in that has a newer
  /// version: its name, the version the copy is based on, and the newest.
  ({String builtin, int base, int latest})? get builtinUpdate {
    final basedOn = workflow?.basedOn;
    if (basedOn == null) return null;
    final builtin = workflows
        .where((w) => w.builtin && w.name == basedOn.builtin)
        .firstOrNull;
    if (builtin == null || builtin.version.version <= basedOn.version) {
      return null;
    }
    return (
      builtin: basedOn.builtin,
      base: basedOn.version,
      latest: builtin.version.version,
    );
  }

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
    List<WorkflowTemplate>? templates,
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
    List<String>? undoStack,
    List<String>? redoStack,
    VersionDiff? Function()? versionDiff,
    BuiltinCompare? Function()? builtinCompare,
  }) => WorkflowBuilderState(
    loaded: loaded ?? this.loaded,
    workflows: workflows ?? this.workflows,
    schema: schema ?? this.schema,
    templates: templates ?? this.templates,
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
    undoStack: undoStack ?? this.undoStack,
    redoStack: redoStack ?? this.redoStack,
    versionDiff: versionDiff == null ? this.versionDiff : versionDiff(),
    builtinCompare: builtinCompare == null
        ? this.builtinCompare
        : builtinCompare(),
  );

  @override
  List<Object?> get props => [
    loaded,
    workflows,
    schema,
    templates,
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
    undoStack,
    redoStack,
    versionDiff,
    builtinCompare,
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
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       super(const WorkflowBuilderState()) {
    on<WorkflowBuilderStarted>(_onStarted, transformer: restartable());
    on<WorkflowOpened>(_onOpened, transformer: restartable());
    on<WorkflowDraftStarted>(_onDraft);
    on<WorkflowImportRequested>(_onImport, transformer: droppable());
    on<WorkflowExportRequested>(_onExport, transformer: droppable());
    on<WorkflowYamlChanged>(_onYaml);
    on<WorkflowDocumentEdited>(_onEdited);
    on<WorkflowUndoRequested>(_onUndo);
    on<WorkflowRedoRequested>(_onRedo);
    on<WorkflowRestored>(_onRestored);
    on<WorkflowRenameRequested>(
      (event, emit) => _update(emit, UpdateWorkflowRequest(name: event.name)),
      transformer: droppable(),
    );
    on<WorkflowArchiveRequested>(
      (event, emit) => _update(
        emit,
        UpdateWorkflowRequest(archived: event.archived),
        workflowId: event.workflowId,
      ),
      transformer: droppable(),
    );
    on<WorkflowCaughtUp>(_onCaughtUp, transformer: droppable());
    on<WorkflowDeleteRequested>(_onDelete, transformer: droppable());
    on<WorkflowVersionsCompared>(_onVersions, transformer: restartable());
    on<WorkflowVersionRestored>(_onRestore, transformer: droppable());
    on<WorkflowBuiltinCompared>(_onBuiltin, transformer: restartable());
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

  final DateTime Function() _now;

  /// Where the last change came from (typing in the YAML, or a value of
  /// the visual editor) and when: such changes in a row are one step of
  /// undo, not one per key.
  ({String source, DateTime at})? _last;

  /// How long changes of one source in a row stay one step of undo.
  static const _coalesce = Duration(seconds: 1);

  /// The most steps of undo the builder keeps.
  static const undoLimit = 100;

  /// The undo stack once the YAML is changed by [source]: the YAML
  /// before the change pushed, unless the change goes on the one before.
  List<String> _undoFor(String? source) {
    final now = _now();
    final last = _last;
    _last = source == null ? null : (source: source, at: now);
    if (source != null &&
        last != null &&
        last.source == source &&
        now.difference(last.at) < _coalesce &&
        state.undoStack.isNotEmpty) {
      return state.undoStack;
    }
    final stack = [...state.undoStack, state.yaml];
    return stack.length > undoLimit
        ? stack.sublist(stack.length - undoLimit)
        : stack;
  }

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
      final templates = await _templates();
      if (templates.isNotEmpty) emit(state.copyWith(templates: templates));
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

  /// The templates, or none while the engine cannot give them.
  Future<List<WorkflowTemplate>> _templates() async {
    try {
      return await _workflows.templates();
    } on Exception {
      return const [];
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
          undoStack: const [],
          redoStack: const [],
        ),
        workflow.yaml,
      ),
    );
    _last = null;
    add(const _WorkflowValidationRequested());
  }

  void _onDraft(
    WorkflowDraftStarted event,
    Emitter<WorkflowBuilderState> emit,
  ) {
    final template = event.template;
    if (template == null || template.id == 'blank') {
      return _draft(emit, template?.yaml ?? draftTemplate.toYaml());
    }
    _draft(emit, template.yaml, name: template.id);
  }

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
          undoStack: const [],
          redoStack: const [],
        ),
        yaml,
      ),
    );
    _last = null;
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
    emit(
      _read(
        state.copyWith(
          notice: () => null,
          undoStack: _undoFor('yaml'),
          redoStack: const [],
        ),
        event.yaml,
      ),
    );
    add(const _WorkflowValidationRequested());
  }

  void _onEdited(
    WorkflowDocumentEdited event,
    Emitter<WorkflowBuilderState> emit,
  ) {
    final document = event.document;
    final yaml = document.toYaml();
    final before = state.document;
    // A value typed in a field goes on the step of undo before it; adding,
    // removing or moving something is a step of its own.
    final source = before != null && _shapeOf(before) == _shapeOf(document)
        ? 'value'
        : null;
    emit(
      state.copyWith(
        yaml: yaml,
        document: () => document,
        shapeIssues: const [],
        validation: WorkflowValidation.checking,
        selection: (event.selection ?? state.selection).within(document),
        notice: () => null,
        undoStack: yaml == state.yaml ? null : _undoFor(source),
        redoStack: yaml == state.yaml ? null : const [],
      ),
    );
    add(const _WorkflowValidationRequested());
  }

  /// What [document] is made of, without its values: its inputs, and the
  /// kinds of the steps of each job of each stage.
  static String _shapeOf(WorkflowDocument document) => [
    document.inputs.length,
    for (final stage in document.stages)
      [
        for (final job in stage.jobs) [for (final step in job.steps) step.kind],
      ],
  ].toString();

  void _onUndo(
    WorkflowUndoRequested event,
    Emitter<WorkflowBuilderState> emit,
  ) {
    final undo = state.undoStack;
    if (undo.isEmpty) return;
    _last = null;
    emit(
      _read(
        state.copyWith(
          undoStack: undo.sublist(0, undo.length - 1),
          redoStack: [...state.redoStack, state.yaml],
          notice: () => null,
        ),
        undo.last,
      ),
    );
    add(const _WorkflowValidationRequested());
  }

  void _onRestored(WorkflowRestored event, Emitter<WorkflowBuilderState> emit) {
    if (event.yaml == state.yaml) return;
    emit(
      _read(
        state.copyWith(
          undoStack: _undoFor(null),
          redoStack: const [],
          notice: () => null,
        ),
        event.yaml,
      ),
    );
    add(const _WorkflowValidationRequested());
  }

  void _onRedo(
    WorkflowRedoRequested event,
    Emitter<WorkflowBuilderState> emit,
  ) {
    final redo = state.redoStack;
    if (redo.isEmpty) return;
    _last = null;
    emit(
      _read(
        state.copyWith(
          undoStack: [...state.undoStack, state.yaml],
          redoStack: redo.sublist(0, redo.length - 1),
          notice: () => null,
        ),
        redo.last,
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
      // The issues the engine found last stay: the document did not get
      // better because the engine went away.
      emit(state.copyWith(validation: WorkflowValidation.unavailable));
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
          : await _workflows.createWorkflow(
              _projectId,
              name: name,
              yaml: yaml,
              basedOn: workflow != null && workflow.builtin
                  ? WorkflowBasedOn(
                      builtin: workflow.name,
                      version: workflow.version.version,
                    )
                  : workflow?.basedOn,
            );
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

  /// Runs [action] as a command of the builder: busy while it runs, and
  /// what went wrong in [WorkflowBuilderState.error].
  Future<void> _command(
    Emitter<WorkflowBuilderState> emit,
    Future<void> Function() action,
  ) async {
    emit(
      state.copyWith(
        command: WorkflowCommand.saving,
        notice: () => null,
        error: () => null,
      ),
    );
    try {
      await action();
    } on Exception catch (error) {
      emit(
        state.copyWith(
          command: WorkflowCommand.none,
          error: () => errorMessage(error),
        ),
      );
    }
  }

  /// Changes the open workflow as [request] says, and reads the list
  /// again: it shows the new name, or that it is archived.
  /// Changes the workflow [workflowId], else the open one of the owner.
  Future<void> _update(
    Emitter<WorkflowBuilderState> emit,
    UpdateWorkflowRequest request, {
    String? workflowId,
  }) async {
    final open = state.workflow;
    final id = workflowId ?? (open == null || open.builtin ? null : open.id);
    if (id == null) return;
    await _command(emit, () async {
      final updated = await _workflows.updateWorkflow(_projectId, id, request);
      final workflows = await _workflows.listWorkflows(_projectId);
      emit(
        state.copyWith(
          workflow: () => state.workflow?.id == id ? updated : state.workflow,
          workflows: workflows,
          command: WorkflowCommand.none,
        ),
      );
    });
  }

  Future<void> _onCaughtUp(
    WorkflowCaughtUp event,
    Emitter<WorkflowBuilderState> emit,
  ) async {
    final update = state.builtinUpdate;
    if (update == null) return;
    await _update(emit, UpdateWorkflowRequest(basedOnVersion: update.latest));
    emit(state.copyWith(builtinCompare: () => null));
  }

  Future<void> _onDelete(
    WorkflowDeleteRequested event,
    Emitter<WorkflowBuilderState> emit,
  ) async {
    final workflow = state.workflow;
    if (workflow == null || workflow.builtin) return;
    await _command(emit, () async {
      await _workflows.deleteWorkflow(_projectId, workflow.id);
      final workflows = await _workflows.listWorkflows(_projectId);
      emit(state.copyWith(workflows: workflows));
      final next =
          workflows.where((w) => !w.builtin).firstOrNull ??
          workflows.firstOrNull;
      if (next == null) {
        emit(state.copyWith(command: WorkflowCommand.none));
        _draft(emit, draftTemplate.toYaml());
      } else {
        await _open(next.id, emit);
      }
      emit(state.copyWith(notice: () => WorkflowDeletedNotice(workflow.name)));
    });
  }

  Future<void> _onVersions(
    WorkflowVersionsCompared event,
    Emitter<WorkflowBuilderState> emit,
  ) async {
    final workflow = state.workflow;
    if (workflow == null) return;
    emit(state.copyWith(versionDiff: () => null, error: () => null));
    try {
      final before = await _workflows.getWorkflow(
        _projectId,
        workflow.id,
        version: event.from,
      );
      final after = await _workflows.getWorkflow(
        _projectId,
        workflow.id,
        version: event.to,
      );
      emit(
        state.copyWith(
          versionDiff: () => VersionDiff(
            from: event.from,
            to: event.to,
            before: before.yaml,
            after: after.yaml,
          ),
        ),
      );
    } on Exception catch (error) {
      emit(state.copyWith(error: () => errorMessage(error)));
    }
  }

  Future<void> _onRestore(
    WorkflowVersionRestored event,
    Emitter<WorkflowBuilderState> emit,
  ) async {
    final workflow = state.workflow;
    if (workflow == null || workflow.builtin) return;
    await _command(emit, () async {
      final old = await _workflows.getWorkflow(
        _projectId,
        workflow.id,
        version: event.version,
      );
      final saved = await _workflows.saveWorkflow(
        _projectId,
        workflow.id,
        old.yaml,
      );
      final workflows = await _workflows.listWorkflows(_projectId);
      emit(
        _read(
          state.copyWith(
            workflows: workflows,
            workflow: () => saved,
            savedYaml: saved.yaml,
            command: WorkflowCommand.none,
            undoStack: _undoFor(null),
            redoStack: const [],
            notice: () => WorkflowRestoredNotice(
              saved.name,
              event.version,
              saved.version.version,
            ),
          ),
          saved.yaml,
        ),
      );
      add(const _WorkflowValidationRequested());
    });
  }

  Future<void> _onBuiltin(
    WorkflowBuiltinCompared event,
    Emitter<WorkflowBuilderState> emit,
  ) async {
    final update = state.builtinUpdate;
    if (update == null) return;
    final builtin = state.workflows.firstWhere(
      (w) => w.builtin && w.name == update.builtin,
    );
    emit(state.copyWith(builtinCompare: () => null, error: () => null));
    try {
      final base = await _workflows.getWorkflow(
        _projectId,
        builtin.id,
        version: update.base,
      );
      final latest = await _workflows.getWorkflow(_projectId, builtin.id);
      emit(
        state.copyWith(
          builtinCompare: () => BuiltinCompare(
            builtin: update.builtin,
            base: update.base,
            latest: latest.version.version,
            baseYaml: base.yaml,
            latestYaml: latest.yaml,
          ),
        ),
      );
    } on Exception catch (error) {
      emit(state.copyWith(error: () => errorMessage(error)));
    }
  }
}

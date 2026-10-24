import 'dart:math';

import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/clock/clock.dart';
import 'package:xp_engine/src/projects/project_exceptions.dart';
import 'package:xp_engine/src/projects/project_repository.dart';
import 'package:xp_engine/src/repositories/event_log.dart';
import 'package:xp_engine/src/scheduler/capability.dart';
import 'package:xp_engine/src/workflows/builtin_workflows.dart';
import 'package:xp_engine/src/workflows/gate_action.dart';
import 'package:xp_engine/src/workflows/step_catalog.dart';
import 'package:xp_engine/src/workflows/workflow_definition.dart';
import 'package:xp_engine/src/workflows/workflow_exceptions.dart';
import 'package:xp_engine/src/workflows/workflow_parser.dart';
import 'package:xp_engine/src/workflows/workflow_repository.dart';
import 'package:xp_engine/src/workflows/workflow_templates.dart';

final _workflowName = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$');

/// A workflow with the version a caller asked for, as the engine stores it.
class StoredWorkflow {
  /// Creates the pair.
  const new(this.workflow, this.version);

  /// The workflow.
  final WorkflowRecord workflow;

  /// One of its versions.
  final WorkflowVersionRecord version;
}

/// Creates, versions, checks and deletes the workflows of a project.
///
/// Every save is a new version (a job keeps the one it ran). The built-in
/// workflows are made for a project the first time its workflows are asked
/// for, and are brought up to date when the engine ships another document for
/// one; they cannot be edited or deleted, but their YAML can be copied into a
/// workflow of the owner's.
class WorkflowService {
  /// Creates the service.
  ///
  /// [random] is for tests; it must be cryptographically secure otherwise.
  new({
    required this._repository,
    required this._projects,
    required this._catalog,
    required this._events,
    required this._clock,
    Random? random,
  }) : _parser = WorkflowParser(_catalog),
       _random = random ?? Random.secure();

  final WorkflowRepository _repository;
  final ProjectRepository _projects;
  final StepCatalog _catalog;
  final WorkflowParser _parser;
  final EventLog _events;
  final Clock _clock;
  final Random _random;

  /// What a workflow document may name: the step types of the engine with
  /// what each does and its typed `with` keys, the gates with their labels,
  /// the capabilities, the matrix axes and the variables.
  WorkflowSchema schema() => WorkflowSchema(
    schema: workflowSchemaVersion,
    steps: [for (final kind in _catalog.kinds) _catalog.describe(kind)!],
    gates: [for (final action in GateAction.values) action.wire],
    gateLabels: {
      for (final action in GateAction.values) action.wire: action.label,
    },
    capabilities: [for (final capability in Capability.values) capability.wire],
    matrixAxes: matrixAxes,
    platforms: platformNames,
    variables: variablePaths,
  );

  /// The documents a new workflow can start from, in the order to offer
  /// them.
  List<WorkflowTemplate> templates() => [
    for (final MapEntry(key: id, value: template) in workflowTemplates.entries)
      WorkflowTemplate(
        id: id,
        title: template.title,
        description: template.description,
        yaml: template.yaml,
      ),
  ];

  /// Checks [yaml] against schema 1 and the step types of the engine.
  ValidateWorkflowResponse validate(String yaml) {
    final issues = _parser.parse(yaml).issues;
    return ValidateWorkflowResponse(valid: issues.isEmpty, issues: issues);
  }

  /// The workflows of the project, by name, each with its newest version.
  ///
  /// Throws a [ProjectNotFoundException] if there is no such project.
  Future<List<WorkflowSummary>> list(String projectId) async {
    await _ensureBuiltIns(projectId);
    return [
      for (final workflow in await _repository.list(projectId))
        _summary(workflow, (await _repository.versions(workflow.id)).last),
    ];
  }

  /// The workflow [workflowId] of the project with the YAML of [version] (the
  /// newest by default).
  ///
  /// Throws a [ProjectNotFoundException] or a [WorkflowNotFoundException].
  Future<Workflow> get(
    String projectId,
    String workflowId, {
    int? version,
  }) async {
    final workflow = await _require(projectId, workflowId);
    final versions = await _repository.versions(workflowId);
    final chosen = version == null
        ? versions.last
        : versions.where((v) => v.version == version).firstOrNull ??
              (throw WorkflowNotFoundException(workflowId, version: version));
    return _detail(workflow, chosen, versions);
  }

  /// The workflow [workflowId] with its newest version, for a dispatch.
  ///
  /// Throws a [ProjectNotFoundException] or a [WorkflowNotFoundException].
  Future<StoredWorkflow> latest(String projectId, String workflowId) async {
    final workflow = await _require(projectId, workflowId);
    return StoredWorkflow(
      workflow,
      (await _repository.versions(workflowId)).last,
    );
  }

  /// The workflow [workflowId] with its version [versionId], to run that
  /// version again.
  ///
  /// Throws a [ProjectNotFoundException] or a [WorkflowNotFoundException]
  /// (also when the version is not one of the workflow).
  Future<StoredWorkflow> stored(
    String projectId,
    String workflowId,
    String versionId,
  ) async {
    final workflow = await _require(projectId, workflowId);
    final version = await _repository.versionById(versionId);
    if (version == null || version.workflowId != workflowId) {
      throw WorkflowNotFoundException(workflowId);
    }
    return StoredWorkflow(workflow, version);
  }

  /// Creates a workflow called [name] from [yaml], at version 1; a copy of
  /// the built-in [basedOn] names, when it names one.
  ///
  /// Throws a [WorkflowNameException], a [WorkflowExistsException], a
  /// [WorkflowInvalidException], a [WorkflowEditException] (no such
  /// built-in) or a [ProjectNotFoundException].
  Future<Workflow> create(
    String projectId, {
    required String name,
    required String yaml,
    WorkflowBasedOn? basedOn,
  }) async {
    await _ensureBuiltIns(projectId);
    await _requireFreeName(projectId, name);
    if (basedOn != null && !builtinWorkflows.containsKey(basedOn.builtin)) {
      throw WorkflowEditException(
        '"${basedOn.builtin}" is not a built-in workflow.',
      );
    }
    final definition = _requireValid(yaml);
    final workflow = WorkflowRecord(
      id: _id('wf'),
      projectId: projectId,
      name: name,
      builtin: false,
      basedOnBuiltin: basedOn?.builtin,
      basedOnVersion: basedOn?.version,
    );
    final first = WorkflowVersionRecord(
      id: _id('wfv'),
      workflowId: workflow.id,
      version: 1,
      yaml: yaml,
      createdAt: _clock.now(),
    );
    await _repository.create(workflow, first);
    _saved(workflow, first);
    return _detail(workflow, first, [first], definition: definition);
  }

  /// Saves [yaml] as the next version of the workflow [workflowId].
  ///
  /// Throws a [WorkflowBuiltinException], a [WorkflowInvalidException], a
  /// [WorkflowNotFoundException] or a [ProjectNotFoundException].
  Future<Workflow> save(
    String projectId,
    String workflowId,
    String yaml,
  ) async {
    final workflow = await _require(projectId, workflowId);
    if (workflow.builtin) throw WorkflowBuiltinException(workflow.name);
    final definition = _requireValid(yaml);
    final next = await _repository.addVersion(
      workflowId: workflowId,
      versionId: _id('wfv'),
      yaml: yaml,
      createdAt: _clock.now(),
    );
    _saved(workflow, next);
    return _detail(
      workflow,
      next,
      await _repository.versions(workflowId),
      definition: definition,
    );
  }

  /// Renames, archives or unarchives the workflow [workflowId], or marks a
  /// copy of a built-in as caught up with a version of it, as [request]
  /// says. No new version is made.
  ///
  /// Throws a [WorkflowBuiltinException], a [WorkflowNameException], a
  /// [WorkflowExistsException], a [WorkflowEditException], a
  /// [WorkflowNotFoundException] or a [ProjectNotFoundException].
  Future<Workflow> update(
    String projectId,
    String workflowId,
    UpdateWorkflowRequest request,
  ) async {
    final workflow = await _require(projectId, workflowId);
    if (workflow.builtin) throw WorkflowBuiltinException(workflow.name);
    final name = request.name;
    if (name != null && name != workflow.name) {
      await _requireFreeName(projectId, name);
    }
    if (request.basedOnVersion != null && workflow.basedOnBuiltin == null) {
      throw WorkflowEditException(
        'Workflow ${workflow.name} is not a copy of a built-in workflow.',
      );
    }
    final archived = request.archived;
    final updated = workflow.copyWith(
      name: name,
      basedOnVersion: request.basedOnVersion,
      archivedAt: archived == null
          ? null
          : () => archived ? workflow.archivedAt ?? _clock.now() : null,
    );
    if (updated != workflow) {
      await _repository.update(updated);
      _events.append(
        WorkflowUpdated(
          workflowId: workflowId,
          projectId: projectId,
          name: updated.name,
          archived: updated.archivedAt != null,
        ),
      );
    }
    final versions = await _repository.versions(workflowId);
    return _detail(updated, versions.last, versions);
  }

  /// Deletes the workflow [workflowId].
  ///
  /// Throws a [WorkflowBuiltinException], a [WorkflowInUseException] (jobs
  /// ran it), a [WorkflowNotFoundException] or a [ProjectNotFoundException].
  Future<void> remove(String projectId, String workflowId) async {
    final workflow = await _require(projectId, workflowId);
    if (workflow.builtin) throw WorkflowBuiltinException(workflow.name);
    await _repository.remove(workflowId);
    _events.append(
      WorkflowRemoved(
        workflowId: workflowId,
        projectId: projectId,
        name: workflow.name,
      ),
    );
  }

  /// The version [versionId] of any workflow: what a job ran.
  Future<WorkflowVersionRecord?> versionById(String versionId) =>
      _repository.versionById(versionId);

  // --------------------------------------------------------------- helpers

  Future<WorkflowRecord> _require(String projectId, String workflowId) async {
    await _ensureBuiltIns(projectId);
    final workflow = await _repository.get(workflowId);
    if (workflow == null || workflow.projectId != projectId) {
      throw WorkflowNotFoundException(workflowId);
    }
    return workflow;
  }

  /// Throws a [WorkflowNameException] or a [WorkflowExistsException] unless
  /// [name] is a name a new workflow of the project can have.
  Future<void> _requireFreeName(String projectId, String name) async {
    if (!_workflowName.hasMatch(name)) throw WorkflowNameException(name);
    if (await _repository.findByName(projectId, name) != null) {
      throw WorkflowExistsException(name);
    }
  }

  /// [yaml] read as a workflow; throws a [WorkflowInvalidException] if it
  /// has issues.
  WorkflowDefinition _requireValid(String yaml) {
    final result = _parser.parse(yaml);
    final definition = result.definition;
    if (!result.isValid || definition == null) {
      throw WorkflowInvalidException(result.issues);
    }
    return definition;
  }

  /// Makes the built-in workflows of the project, and gives a built-in a new
  /// version when the engine's document for it changed.
  Future<void> _ensureBuiltIns(String projectId) async {
    if (await _projects.get(projectId) == null) {
      throw ProjectNotFoundException(projectId);
    }
    for (final MapEntry(key: name, value: yaml) in builtinWorkflows.entries) {
      final existing = await _repository.findByName(projectId, name);
      if (existing == null) {
        final workflow = WorkflowRecord(
          id: _id('wf'),
          projectId: projectId,
          name: name,
          builtin: true,
        );
        await _repository.create(
          workflow,
          WorkflowVersionRecord(
            id: _id('wfv'),
            workflowId: workflow.id,
            version: 1,
            yaml: yaml,
            createdAt: _clock.now(),
          ),
        );
      } else if (existing.builtin) {
        final newest = (await _repository.versions(existing.id)).last;
        if (newest.yaml != yaml) {
          await _repository.addVersion(
            workflowId: existing.id,
            versionId: _id('wfv'),
            yaml: yaml,
            createdAt: _clock.now(),
          );
        }
      }
    }
  }

  void _saved(WorkflowRecord workflow, WorkflowVersionRecord version) =>
      _events.append(
        WorkflowSaved(
          workflowId: workflow.id,
          projectId: workflow.projectId,
          name: workflow.name,
          version: version.version,
        ),
      );

  WorkflowSummary _summary(
    WorkflowRecord workflow,
    WorkflowVersionRecord newest,
  ) {
    final definition = _parser.parse(newest.yaml).definition;
    return WorkflowSummary(
      id: workflow.id,
      projectId: workflow.projectId,
      name: workflow.name,
      builtin: workflow.builtin,
      version: _info(newest),
      title: definition?.name,
      description: definition?.description,
      basedOn: _basedOn(workflow),
      archivedAt: workflow.archivedAt,
    );
  }

  /// [chosen] of [workflow] for a client; [definition] is [chosen] already
  /// read, when the caller has it.
  Workflow _detail(
    WorkflowRecord workflow,
    WorkflowVersionRecord chosen,
    List<WorkflowVersionRecord> versions, {
    WorkflowDefinition? definition,
  }) => Workflow(
    id: workflow.id,
    projectId: workflow.projectId,
    name: workflow.name,
    builtin: workflow.builtin,
    version: _info(chosen),
    versions: [for (final version in versions) _info(version)],
    yaml: chosen.yaml,
    inputs: [
      for (final input
          in (definition ?? _parser.parse(chosen.yaml).definition)?.inputs ??
              const <InputDefinition>[])
        input.toWire(),
    ],
    basedOn: _basedOn(workflow),
    archivedAt: workflow.archivedAt,
  );

  static WorkflowBasedOn? _basedOn(WorkflowRecord workflow) =>
      switch ((workflow.basedOnBuiltin, workflow.basedOnVersion)) {
        (final String builtin, final int version) => WorkflowBasedOn(
          builtin: builtin,
          version: version,
        ),
        _ => null,
      };

  WorkflowVersionInfo _info(WorkflowVersionRecord version) =>
      WorkflowVersionInfo(
        id: version.id,
        version: version.version,
        createdAt: version.createdAt,
      );

  String _id(String prefix) {
    final hex = List.generate(
      8,
      (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    );
    return '${prefix}_${hex.join()}';
  }
}

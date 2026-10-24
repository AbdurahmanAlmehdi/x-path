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

  /// Creates a workflow called [name] from [yaml], at version 1.
  ///
  /// Throws a [WorkflowNameException], a [WorkflowExistsException], a
  /// [WorkflowInvalidException] or a [ProjectNotFoundException].
  Future<Workflow> create(
    String projectId, {
    required String name,
    required String yaml,
  }) async {
    await _ensureBuiltIns(projectId);
    if (!_workflowName.hasMatch(name)) throw WorkflowNameException(name);
    if (await _repository.findByName(projectId, name) != null) {
      throw WorkflowExistsException(name);
    }
    _requireValid(yaml);
    final workflow = WorkflowRecord(
      id: _id('wf'),
      projectId: projectId,
      name: name,
      builtin: false,
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
    return _detail(workflow, first, [first]);
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
    _requireValid(yaml);
    final next = await _repository.addVersion(
      workflowId: workflowId,
      versionId: _id('wfv'),
      yaml: yaml,
      createdAt: _clock.now(),
    );
    _saved(workflow, next);
    return _detail(workflow, next, await _repository.versions(workflowId));
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

  void _requireValid(String yaml) {
    final result = _parser.parse(yaml);
    if (!result.isValid) throw WorkflowInvalidException(result.issues);
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
    );
  }

  Workflow _detail(
    WorkflowRecord workflow,
    WorkflowVersionRecord chosen,
    List<WorkflowVersionRecord> versions,
  ) => Workflow(
    id: workflow.id,
    projectId: workflow.projectId,
    name: workflow.name,
    builtin: workflow.builtin,
    version: _info(chosen),
    versions: [for (final version in versions) _info(version)],
    yaml: chosen.yaml,
    inputs: [
      for (final input
          in _parser.parse(chosen.yaml).definition?.inputs ??
              const <InputDefinition>[])
        input.toWire(),
    ],
  );

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

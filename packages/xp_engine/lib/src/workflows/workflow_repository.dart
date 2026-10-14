import 'package:equatable/equatable.dart';
import 'package:xp_engine/src/workflows/workflow_exceptions.dart';

/// What the engine stores about a workflow.
class WorkflowRecord extends Equatable {
  /// Creates a record.
  const new({
    required this.id,
    required this.projectId,
    required this.name,
    required this.builtin,
  });

  /// The engine's id.
  final String id;

  /// The project it belongs to.
  final String projectId;

  /// Its name, unique in the project.
  final String name;

  /// Whether the engine made it.
  final bool builtin;

  @override
  List<Object?> get props => [id, projectId, name, builtin];
}

/// One saved version of a workflow.
class WorkflowVersionRecord extends Equatable {
  /// Creates a record.
  const new({
    required this.id,
    required this.workflowId,
    required this.version,
    required this.yaml,
    required this.createdAt,
  });

  /// The engine's id; a job keeps it as `workflowVersionId`.
  final String id;

  /// The workflow.
  final String workflowId;

  /// The number of the version, from 1.
  final int version;

  /// The document.
  final String yaml;

  /// When it was saved.
  final DateTime createdAt;

  @override
  List<Object?> get props => [id, workflowId, version, yaml, createdAt];
}

/// Where workflows and their versions are kept.
///
/// A version is never changed or deleted while a job refers to it: a saved
/// workflow gets a new version, and a job keeps the one it ran. `xp_adapters`
/// has the SQLite implementation.
abstract interface class WorkflowRepository {
  /// The workflows of [projectId], by name.
  Future<List<WorkflowRecord>> list(String projectId);

  /// The workflow [id], or `null`.
  Future<WorkflowRecord?> get(String id);

  /// The workflow called [name] in [projectId], or `null`.
  Future<WorkflowRecord?> findByName(String projectId, String name);

  /// Stores a new workflow with its first version.
  Future<void> create(WorkflowRecord workflow, WorkflowVersionRecord first);

  /// Stores [yaml] as the next version of [workflowId], with the id
  /// [versionId], and returns it. The number is one more than the newest.
  Future<WorkflowVersionRecord> addVersion({
    required String workflowId,
    required String versionId,
    required String yaml,
    required DateTime createdAt,
  });

  /// The versions of [workflowId], oldest first.
  Future<List<WorkflowVersionRecord>> versions(String workflowId);

  /// The version with [id], or `null`.
  Future<WorkflowVersionRecord?> versionById(String id);

  /// Deletes the workflow [id] with its versions. Returns whether there was
  /// one.
  ///
  /// Throws a `WorkflowInUseException` if jobs refer to a version of it.
  Future<bool> remove(String id);
}

/// A [WorkflowRepository] that forgets everything on exit.
class InMemoryWorkflowRepository implements WorkflowRepository {
  final _workflows = <String, WorkflowRecord>{};
  final _versions = <String, List<WorkflowVersionRecord>>{};

  /// The ids of the workflow versions that jobs refer to: [remove] refuses
  /// their workflows.
  final usedVersions = <String>{};

  @override
  Future<List<WorkflowRecord>> list(String projectId) async =>
      _workflows.values.where((w) => w.projectId == projectId).toList()
        ..sort((a, b) => a.name.compareTo(b.name));

  @override
  Future<WorkflowRecord?> get(String id) async => _workflows[id];

  @override
  Future<WorkflowRecord?> findByName(String projectId, String name) async =>
      _workflows.values
          .where((w) => w.projectId == projectId && w.name == name)
          .firstOrNull;

  @override
  Future<void> create(
    WorkflowRecord workflow,
    WorkflowVersionRecord first,
  ) async {
    _workflows[workflow.id] = workflow;
    _versions[workflow.id] = [first];
  }

  @override
  Future<WorkflowVersionRecord> addVersion({
    required String workflowId,
    required String versionId,
    required String yaml,
    required DateTime createdAt,
  }) async {
    final versions = _versions[workflowId]!;
    final next = WorkflowVersionRecord(
      id: versionId,
      workflowId: workflowId,
      version: versions.last.version + 1,
      yaml: yaml,
      createdAt: createdAt,
    );
    versions.add(next);
    return next;
  }

  @override
  Future<List<WorkflowVersionRecord>> versions(String workflowId) async =>
      List.of(_versions[workflowId] ?? const []);

  @override
  Future<WorkflowVersionRecord?> versionById(String id) async =>
      [for (final versions in _versions.values) ...versions]
          .where((version) => version.id == id)
          .firstOrNull;

  @override
  Future<bool> remove(String id) async {
    final versions = _versions[id] ?? const [];
    if (versions.any((version) => usedVersions.contains(version.id))) {
      throw WorkflowInUseException(id);
    }
    _versions.remove(id);
    return _workflows.remove(id) != null;
  }
}

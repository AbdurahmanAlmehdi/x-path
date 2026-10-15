import 'package:xp_api/xp_api.dart';
import 'package:xp_repositories/src/session/engine_session.dart';
import 'package:xp_repositories/src/workflows/dispatch_preview.dart';
import 'package:xp_repositories/src/workflows/workflow_outline.dart';

/// The workflows of the engine of an [EngineSession], and dispatching them.
class WorkflowsRepository {
  /// Creates the repository.
  const new(this._session);

  final EngineSession _session;

  /// The workflows of [projectId], built-in first.
  Future<List<WorkflowSummary>> listWorkflows(String projectId) =>
      _session.call((client) => client.listWorkflows(projectId));

  /// The workflow [workflowId] of [projectId], at [version] or the newest.
  Future<Workflow> getWorkflow(
    String projectId,
    String workflowId, {
    int? version,
  }) => _session.call(
    (client) => client.getWorkflow(projectId, workflowId, version: version),
  );

  /// What a workflow document of the engine may name, for the builder.
  Future<WorkflowSchema> schema() =>
      _session.call((client) => client.getWorkflowSchema());

  /// The issues the engine finds in [yaml], with their lines. Nothing is
  /// saved.
  Future<ValidateWorkflowResponse> validate(String projectId, String yaml) =>
      _session.call((client) => client.validateWorkflow(projectId, yaml));

  /// Creates the workflow [name] of [projectId] from [yaml], at version 1.
  Future<Workflow> createWorkflow(
    String projectId, {
    required String name,
    required String yaml,
  }) => _session.call(
    (client) => client.createWorkflow(
      projectId,
      CreateWorkflowRequest(name: name, yaml: yaml),
    ),
  );

  /// Saves [yaml] as the next version of [workflowId] of [projectId].
  Future<Workflow> saveWorkflow(
    String projectId,
    String workflowId,
    String yaml,
  ) => _session.call(
    (client) => client.saveWorkflow(projectId, workflowId, yaml),
  );

  /// The exact version of the workflow that [run] runs.
  Future<Workflow> workflowOf(Run run) async {
    final newest = await getWorkflow(run.projectId, run.workflowId);
    if (newest.version.id == run.workflowVersionId) return newest;
    final version = newest.versions
        .where((version) => version.id == run.workflowVersionId)
        .firstOrNull;
    if (version == null) return newest;
    return await getWorkflow(
      run.projectId,
      run.workflowId,
      version: version.version,
    );
  }

  /// What dispatching [workflow] in [project] with [request] would start,
  /// read from the runners, gates and credentials the engine has now.
  Future<DispatchPreview> preview({
    required Project project,
    required Workflow workflow,
    required DispatchRequest request,
  }) async => DispatchPreview.plan(
    project: project,
    workflow: WorkflowOutline.parse(workflow.yaml),
    request: request,
    runners: await _session.call((client) => client.listRunners()),
    gates: await _session.call((client) => client.getGates(project.id)),
    credentials: await _session.call(
      (client) => client.listCredentials(project.id),
    ),
  );

  /// Dispatches [workflowId] of [projectId] with [request].
  Future<Run> dispatch(
    String projectId,
    String workflowId,
    DispatchRequest request,
  ) => _session.call(
    (client) => client.dispatchWorkflow(projectId, workflowId, request),
  );
}

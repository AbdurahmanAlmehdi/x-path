import 'package:xp_api/xp_api.dart';
import 'package:xp_repositories/src/session/engine_session.dart';

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

  /// What dispatching [workflowId] of [projectId] with [request] would
  /// start, planned by the engine without starting it (UX-01).
  Future<DispatchPlan> plan(
    String projectId,
    String workflowId,
    DispatchRequest request,
  ) => _session.call(
    (client) => client.planDispatch(projectId, workflowId, request),
  );

  /// The inputs the last dispatch of [workflowId] in [projectId] from this
  /// app gave, kept with the engine's offline cache; empty before the first.
  Future<Map<String, Object?>> lastInputs(
    String projectId,
    String workflowId,
  ) async =>
      switch (await _session.cache.read(_inputsKey(projectId, workflowId))) {
        final Map<String, Object?> inputs => inputs,
        _ => const {},
      };

  /// The workflow the last dispatch in [projectId] from this app ran, if
  /// any: what the Dispatch sheet offers first.
  Future<String?> lastWorkflow(String projectId) async =>
      switch (await _session.cache.read('dispatch-workflow.$projectId')) {
        final String id => id,
        _ => null,
      };

  /// Keeps [workflowId] as the last workflow dispatched in [projectId] and
  /// [inputs] as its last inputs.
  Future<void> rememberDispatch(
    String projectId,
    String workflowId,
    Map<String, Object?> inputs,
  ) async {
    await _session.cache.write('dispatch-workflow.$projectId', workflowId);
    await _session.cache.write(_inputsKey(projectId, workflowId), inputs);
  }

  static String _inputsKey(String projectId, String workflowId) =>
      'dispatch-inputs.$projectId.$workflowId';

  /// Dispatches [workflowId] of [projectId] with [request].
  Future<Run> dispatch(
    String projectId,
    String workflowId,
    DispatchRequest request,
  ) => _session.call(
    (client) => client.dispatchWorkflow(projectId, workflowId, request),
  );
}

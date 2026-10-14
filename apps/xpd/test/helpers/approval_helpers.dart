import 'dart:convert';

import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import 'test_engine.dart';
import 'workflow_helpers.dart';

/// The commit the demo approvals are about.
const approvalSha = 'a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1';

/// An engine with one project and a token of every kind, to ask the approval
/// endpoints as each of them.
class ApprovalClient {
  new _(this.engine, this.projectId, this.secrets);

  /// Starts an engine whose gates ask its approvals.
  static Future<ApprovalClient> start() async {
    final engine = await TestEngine.start(realApprovals: true);
    final workflows = await WorkflowClient.add(engine);
    final secrets = <DeviceTokenKind, String>{
      DeviceTokenKind.app: engine.secret,
      for (final kind in [
        DeviceTokenKind.cli,
        DeviceTokenKind.mcp,
        DeviceTokenKind.runner,
      ])
        kind: (await engine.tokens.issue(
          name: '${kind.name} token',
          kind: kind,
        )).secret,
    };
    return ApprovalClient._(engine, workflows.projectId, secrets);
  }

  final TestEngine engine;
  final String projectId;

  /// The bearer secret of a token of each kind.
  final Map<DeviceTokenKind, String> secrets;

  /// Sends a request as a token of [kind].
  Future<RawResponse> send(
    String method,
    String path, {
    DeviceTokenKind kind = DeviceTokenKind.app,
    Object? body,
    String? rawBody,
  }) => engine.request(
    path,
    method: method,
    token: secrets[kind],
    body: rawBody ?? (body == null ? null : jsonEncode(body)),
  );

  /// A job reaches a gate: the request of the approval it creates.
  Future<String> ask({
    GateAction action = GateAction.prodRelease,
    String sha = approvalSha,
    String? version = '1.2.3+45',
  }) async {
    final decision = await engine.approvals.check(
      GateRequest(
        action: action,
        projectId: projectId,
        sha: sha,
        version: version,
        jobId: 'job_x',
      ),
    );
    return (decision as GatePending).approvalId!;
  }

  /// The approval [id] as the API shows it.
  Future<Approval> read(String id) async =>
      Approval.fromJson((await send('GET', '/approvals/$id')).json);

  /// The events logged so far.
  Future<List<EngineEvent>> logged() async {
    final seen = <EngineEvent>[];
    final subscription = engine.events
        .subscribe(after: 0)
        .listen((entry) => seen.add(entry.event));
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();
    return seen;
  }

  Future<void> close() => engine.close();
}

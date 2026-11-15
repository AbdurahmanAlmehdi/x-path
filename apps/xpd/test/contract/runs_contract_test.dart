@Tags(['contract'])
library;

import 'package:test/test.dart';
import 'package:xp_api/testing.dart';
import 'package:xp_api/xp_api.dart';

import '../helpers/test_engine.dart';
import '../helpers/workflow_helpers.dart';

/// The origin of a run and the role a run needs (ADR 0017), checked against
/// `openapi.yaml`.
void main() {
  late OpenApiContract contract;
  late TestEngine engine;
  late WorkflowClient client;
  late String workflowId;

  setUpAll(() async => contract = await OpenApiContract.load());
  setUp(() async {
    engine = await TestEngine.start();
    client = await WorkflowClient.add(engine);
    workflowId = await client.create('echo', echoWorkflow);
  });
  tearDown(() => engine.close());

  Future<RawResponse> expectContract(
    String method,
    String path,
    int status, {
    required String token,
  }) async {
    final response = await engine.request(path, method: method, token: token);
    expect(response.statusCode, status, reason: response.body);
    contract.expectResponse(
      method: method,
      path: path,
      statusCode: response.statusCode,
      contentType: response.contentType,
      body: response.body,
    );
    return response;
  }

  String dispatch() => '${client.base}/$workflowId/dispatch';

  test(
    'a run of a cli token and one of an mcp token carry their origin',
    () async {
      for (final (kind, origin) in [
        (DeviceTokenKind.cli, RunOriginKind.person),
        (DeviceTokenKind.mcp, RunOriginKind.agent),
      ]) {
        final token = await engine.tokenFor(PersonRole.developer, kind: kind);
        final run = Run.fromJson(
          (await expectContract('POST', dispatch(), 202, token: token)).json,
        );

        final read = await expectContract(
          'GET',
          '/runs/${run.id}',
          200,
          token: token,
        );
        expect(Run.fromJson(read.json).origin?.kind, origin);
        expect(Run.fromJson(read.json).origin?.personName, 'developer');
      }
    },
  );

  test('a viewer gets 403 on dispatch, run again and cancel', () async {
    final viewer = await engine.tokenFor(PersonRole.viewer);
    final run = Run.fromJson((await client.dispatch(workflowId)).json);

    await expectContract('POST', dispatch(), 403, token: viewer);
    await expectContract(
      'POST',
      '/runs/${run.id}/run-again',
      403,
      token: viewer,
    );
    await expectContract('POST', '/runs/${run.id}/cancel', 403, token: viewer);
  });
}

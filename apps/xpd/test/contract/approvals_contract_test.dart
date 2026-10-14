@Tags(['contract'])
library;

import 'package:test/test.dart';
import 'package:xp_api/testing.dart';
import 'package:xp_api/xp_api.dart';

import '../helpers/approval_helpers.dart';
import '../helpers/test_engine.dart';

/// Every response of the approval and gate endpoints is checked against
/// `openapi.yaml`.
void main() {
  late OpenApiContract contract;
  late ApprovalClient client;

  setUpAll(() async => contract = await OpenApiContract.load());
  setUp(() async => client = await ApprovalClient.start());
  tearDown(() => client.close());

  void expectContract(
    RawResponse response, {
    required String path,
    required int status,
    String method = 'GET',
  }) {
    expect(response.statusCode, status, reason: response.body);
    contract.expectResponse(
      method: method,
      path: path,
      statusCode: response.statusCode,
      contentType: response.contentType,
      body: response.body,
    );
  }

  test('request bodies match their schemas', () {
    for (final (schema, body) in <(String, Object)>[
      ('DecisionRequest', <String, Object>{}),
      ('DecisionRequest', {'reason': 'checked'}),
      (
        'ProjectGates',
        {
          'gates': {'prod_release': true, 'push': false},
        },
      ),
      ('ProjectGates', {'gates': <String, bool>{}}),
    ]) {
      expect(contract.validateSchema(schema, body), isEmpty, reason: schema);
    }
    expect(
      contract.validateSchema('DecisionRequest', {'reason': 1}),
      isNotEmpty,
    );
    expect(
      contract.validateSchema('ProjectGates', {
        'gates': {'launch_rocket': true},
      }),
      isNotEmpty,
    );
  });

  group('approvals', () {
    test('GET list 200, 400 and 401', () async {
      await client.ask();

      expectContract(
        await client.send('GET', '/approvals'),
        path: '/approvals',
        status: 200,
      );
      expectContract(
        await client.send('GET', '/approvals?state=pending'),
        path: '/approvals',
        status: 200,
      );
      expectContract(
        await client.send('GET', '/approvals?state=maybe'),
        path: '/approvals',
        status: 400,
      );
      expectContract(
        await client.engine.request('/approvals', token: ''),
        path: '/approvals',
        status: 401,
      );
    });

    test('GET one 200, 401 and 404', () async {
      final id = await client.ask();

      expectContract(
        await client.send('GET', '/approvals/$id'),
        path: '/approvals/$id',
        status: 200,
      );
      expectContract(
        await client.engine.request('/approvals/$id', token: ''),
        path: '/approvals/$id',
        status: 401,
      );
      expectContract(
        await client.send('GET', '/approvals/apr_nope'),
        path: '/approvals/apr_nope',
        status: 404,
      );
    });

    test('GET one of every state', () async {
      final approved = await client.ask();
      final denied = await client.ask(version: '2');
      final pending = await client.ask(version: '3');
      final expired = await client.ask(version: '4');
      await client.send('POST', '/approvals/$approved/approve');
      await client.send(
        'POST',
        '/approvals/$denied/deny',
        body: {'reason': 'no'},
      );
      client.engine.clock.advance(const Duration(hours: 24));
      await client.send('GET', '/approvals/$expired');

      for (final id in [approved, denied, pending, expired]) {
        expectContract(
          await client.send('GET', '/approvals/$id'),
          path: '/approvals/$id',
          status: 200,
        );
      }
    });

    test('POST approve 200, 400, 401, 403, 404 and 409', () async {
      final id = await client.ask();
      final path = '/approvals/$id/approve';

      expectContract(
        await client.send('POST', path, rawBody: '{"reason": 5}'),
        path: path,
        method: 'POST',
        status: 400,
      );
      expectContract(
        await client.engine.request(path, method: 'POST', token: ''),
        path: path,
        method: 'POST',
        status: 401,
      );
      expectContract(
        await client.send('POST', path, kind: DeviceTokenKind.mcp),
        path: path,
        method: 'POST',
        status: 403,
      );
      expectContract(
        await client.send('POST', '/approvals/apr_nope/approve'),
        path: '/approvals/apr_nope/approve',
        method: 'POST',
        status: 404,
      );
      expectContract(
        await client.send('POST', path),
        path: path,
        method: 'POST',
        status: 200,
      );
      expectContract(
        await client.send('POST', path),
        path: path,
        method: 'POST',
        status: 409,
      );
    });

    test('POST deny 200, 403 and 409', () async {
      final id = await client.ask();
      final path = '/approvals/$id/deny';

      expectContract(
        await client.send('POST', path, kind: DeviceTokenKind.runner),
        path: path,
        method: 'POST',
        status: 403,
      );
      expectContract(
        await client.send(
          'POST',
          path,
          kind: DeviceTokenKind.cli,
          body: {'reason': 'wrong build'},
        ),
        path: path,
        method: 'POST',
        status: 200,
      );
      expectContract(
        await client.send('POST', path),
        path: path,
        method: 'POST',
        status: 409,
      );
    });
  });

  group('gates', () {
    test('GET 200, 401 and 404', () async {
      final path = '/projects/${client.projectId}/gates';

      expectContract(await client.send('GET', path), path: path, status: 200);
      expectContract(
        await client.engine.request(path, token: ''),
        path: path,
        status: 401,
      );
      expectContract(
        await client.send('GET', '/projects/prj_nope/gates'),
        path: '/projects/prj_nope/gates',
        status: 404,
      );
    });

    test('PUT 200, 400, 401, 403 and 404', () async {
      final path = '/projects/${client.projectId}/gates';
      const body = {
        'gates': {'push': false},
      };

      expectContract(
        await client.send('PUT', path, body: body),
        path: path,
        method: 'PUT',
        status: 200,
      );
      expectContract(
        await client.send('PUT', path, rawBody: '{"gates": 5}'),
        path: path,
        method: 'PUT',
        status: 400,
      );
      expectContract(
        await client.engine.request(path, method: 'PUT', token: ''),
        path: path,
        method: 'PUT',
        status: 401,
      );
      expectContract(
        await client.send('PUT', path, kind: DeviceTokenKind.mcp, body: body),
        path: path,
        method: 'PUT',
        status: 403,
      );
      expectContract(
        await client.send(
          'PUT',
          path,
          kind: DeviceTokenKind.cli,
          body: {
            'gates': {'merge': false},
          },
        ),
        path: path,
        method: 'PUT',
        status: 403,
      );
      expectContract(
        await client.send(
          'PUT',
          '/projects/prj_nope/gates',
          body: {'gates': <String, bool>{}},
        ),
        path: '/projects/prj_nope/gates',
        method: 'PUT',
        status: 404,
      );
    });
  });
}

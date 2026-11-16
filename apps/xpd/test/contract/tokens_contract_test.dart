@Tags(['contract'])
library;

import 'dart:convert';

import 'package:test/test.dart';
import 'package:xp_api/testing.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart' show TokenService;

import '../helpers/test_engine.dart';

/// Every response of the token, status and doctor endpoints (U5b) is checked
/// against `openapi.yaml`.
void main() {
  late OpenApiContract contract;
  late TestEngine engine;
  late String mcp;
  late String runner;

  setUpAll(() async => contract = await OpenApiContract.load());
  setUp(() async {
    engine = await TestEngine.start();
    mcp = (await engine.tokens.issue(
      name: 'agent',
      kind: DeviceTokenKind.mcp,
    )).secret;
    runner = (await engine.tokens.issue(
      name: 'mac mini',
      kind: DeviceTokenKind.runner,
    )).secret;
  });
  tearDown(() => engine.close());

  Future<void> expectContract(
    String method,
    String path,
    int status, {
    String? token,
    Object? body,
  }) async {
    final response = await engine.request(
      path,
      method: method,
      token: token,
      body: body == null ? null : jsonEncode(body),
    );
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
    expect(
      contract.validateSchema('CreateTokenRequest', {
        'name': 'xp',
        'kind': 'cli',
      }),
      isEmpty,
    );
    expect(
      contract.validateSchema('CreateTokenRequest', {
        'name': 'xp',
        'kind': 'app',
      }),
      isNotEmpty,
    );
  });

  test('POST /tokens 201, 400, 401 and 403', () async {
    await expectContract(
      'POST',
      '/tokens',
      201,
      body: {'name': 'xp on MacBook', 'kind': 'cli'},
    );
    await expectContract('POST', '/tokens', 400, body: {'name': 'x'});
    await expectContract('POST', '/tokens', 401, token: '', body: {});
    await expectContract(
      'POST',
      '/tokens',
      403,
      token: mcp,
      body: {'name': 'x', 'kind': 'cli'},
    );
  });

  test('GET /tokens 200, 401 and 403', () async {
    await expectContract('GET', '/tokens', 200);
    await expectContract('GET', '/tokens', 401, token: '');
    await expectContract('GET', '/tokens', 403, token: mcp);
    await expectContract('GET', '/tokens', 403, token: runner);
  });

  test('DELETE /tokens/{id} 204, 401, 403 and 404', () async {
    final created = CreatedToken.fromJson(
      (await engine.request(
        '/tokens',
        method: 'POST',
        body: jsonEncode({'name': 'xp', 'kind': 'cli'}),
      )).json,
    );
    final path = '/tokens/${created.info.id}';

    final viewer = await engine.tokenFor(PersonRole.viewer);
    await expectContract('DELETE', path, 404, token: viewer);
    await expectContract('DELETE', path, 401, token: '');
    await expectContract('DELETE', path, 403, token: mcp);
    await expectContract('DELETE', path, 204);
    await expectContract('DELETE', path, 404);
  });

  test('GET /status 200, 401 and 403', () async {
    await expectContract('GET', '/status', 200, token: mcp);
    await expectContract('GET', '/status', 401, token: '');
    await expectContract('GET', '/status', 403, token: runner);
  });

  test('401 for an expired token says so', () async {
    engine.clock.advance(TokenService.clientTokenLifetime);

    final response = await engine.request('/status', token: mcp);

    expect(response.statusCode, 401);
    contract.expectResponse(
      method: 'GET',
      path: '/status',
      statusCode: response.statusCode,
      contentType: response.contentType,
      body: response.body,
    );
    final error = ApiError.fromJson(
      response.json['error'] as Map<String, dynamic>,
    );
    expect(error.code, ApiErrorCode.unauthorized);
    expect(error.details, {
      'reason': ErrorReason.tokenExpired,
      'expiredAt': engine.clock.now().toIso8601String(),
    });
    expect(
      error.message,
      'The bearer token expired at ${engine.clock.now().toIso8601String()}.',
    );
  });

  test('GET /doctor 200, 401 and 403', () async {
    await expectContract('GET', '/doctor', 200);
    await expectContract('GET', '/doctor', 401, token: '');
    await expectContract('GET', '/doctor', 403, token: runner);
  });
}

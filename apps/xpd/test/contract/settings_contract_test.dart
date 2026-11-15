@Tags(['contract'])
library;

import 'dart:convert';

import 'package:test/test.dart';
import 'package:xp_api/testing.dart';
import 'package:xp_api/xp_api.dart';

import '../helpers/test_engine.dart';

/// Every response of `/settings/public-url` (ADR 0018) is checked against
/// `openapi.yaml`.
void main() {
  late OpenApiContract contract;
  late TestEngine engine;

  setUpAll(() async => contract = await OpenApiContract.load());
  setUp(() async => engine = await TestEngine.start());
  tearDown(() => engine.close());

  const path = '/settings/public-url';

  Future<RawResponse> expectContract(
    String method,
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
    return response;
  }

  test('request bodies match their schemas', () {
    expect(
      contract.validateSchema('SetPublicUrlRequest', {'url': null}),
      isEmpty,
    );
    expect(
      contract.validateSchema('SetPublicUrlRequest', const {}),
      isNotEmpty,
    );
  });

  test('GET and PUT 200, 400, 401 and 403', () async {
    final viewer = await engine.tokenFor(PersonRole.viewer);

    await expectContract('GET', 200, token: viewer);
    await expectContract('GET', 401, token: '');
    final set = await expectContract(
      'PUT',
      200,
      body: {'url': 'https://xpath.example.com/'},
    );
    expect(set.json, {'url': 'https://xpath.example.com'});
    expect((await expectContract('GET', 200)).json, set.json);
    await expectContract('PUT', 400, body: {'url': 'http://a.example'});
    await expectContract('PUT', 400, body: const {});
    await expectContract('PUT', 403, token: viewer, body: {'url': null});
    expect(
      (await expectContract('PUT', 200, body: {'url': null})).json,
      isEmpty,
    );
  });
}

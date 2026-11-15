@Tags(['contract'])
library;

import 'dart:convert';

import 'package:test/test.dart';
import 'package:xp_api/testing.dart';
import 'package:xp_api/xp_api.dart';

import '../helpers/test_engine.dart';

/// Every response of the browser session endpoints and of the sign-in codes
/// (ADR 0018) is checked against `openapi.yaml`.
void main() {
  late OpenApiContract contract;
  late TestEngine engine;

  setUpAll(() async => contract = await OpenApiContract.load());
  setUp(() async => engine = await TestEngine.start());
  tearDown(() => engine.close());

  Future<RawResponse> expectContract(
    String method,
    String path,
    int status, {
    String? token,
    Map<String, String> headers = const {},
    Object? body,
    String? documentedPath,
  }) async {
    final response = await engine.request(
      path,
      method: method,
      token: token,
      headers: headers,
      body: body == null ? null : jsonEncode(body),
    );
    expect(response.statusCode, status, reason: response.body);
    contract.expectResponse(
      method: method,
      path: documentedPath ?? path,
      statusCode: response.statusCode,
      contentType: response.contentType,
      body: response.body,
    );
    return response;
  }

  test('request bodies match their schemas', () {
    expect(
      contract.validateSchema('SignInRequest', {'code': 'abcd-efgh'}),
      isEmpty,
    );
    expect(contract.validateSchema('SignInRequest', const {}), isNotEmpty);
  });

  test('POST /people/{id}/sign-in-codes 201, 401, 403 and 404', () async {
    const documented = '/people/{id}/sign-in-codes';
    final created = await expectContract(
      'POST',
      '/people/${testOwner.id}/sign-in-codes',
      201,
      documentedPath: documented,
    );
    expect(contract.validateSchema('SignInCode', created.json), isEmpty);
    await expectContract(
      'POST',
      '/people/${testOwner.id}/sign-in-codes',
      401,
      token: '',
      documentedPath: documented,
    );
    await expectContract(
      'POST',
      '/people/${testOwner.id}/sign-in-codes',
      403,
      token: await engine.tokenFor(PersonRole.viewer),
      documentedPath: documented,
    );
    await expectContract(
      'POST',
      '/people/per_nope/sign-in-codes',
      404,
      documentedPath: documented,
    );
  });

  test('POST /session 200, 400, 401, 403 and 429', () async {
    final origin = {'origin': engine.loopbackOrigin};
    final code = (await engine.signIn.issue(testOwner.id)).code;

    await expectContract(
      'POST',
      '/session',
      200,
      token: '',
      headers: origin,
      body: {'code': code},
    );
    await expectContract(
      'POST',
      '/session',
      400,
      token: '',
      headers: origin,
      body: const {},
    );
    await expectContract(
      'POST',
      '/session',
      403,
      token: '',
      headers: {'origin': 'http://evil.example'},
      body: {'code': code},
    );
    await expectContract(
      'POST',
      '/session',
      403,
      token: '',
      body: {'code': code},
    );
    for (var i = 0; i < 20; i++) {
      await expectContract(
        'POST',
        '/session',
        401,
        token: '',
        headers: origin,
        body: {'code': code},
      );
    }
    await expectContract(
      'POST',
      '/session',
      429,
      token: '',
      headers: origin,
      body: {'code': code},
    );
  });

  test('DELETE /session 204, 401 and 403', () async {
    final cookie = await engine.signInBrowser();

    await expectContract(
      'DELETE',
      '/session',
      403,
      token: '',
      headers: {'cookie': cookie},
    );
    await expectContract('DELETE', '/session', 403);
    await expectContract(
      'DELETE',
      '/session',
      204,
      token: '',
      headers: engine.browser(cookie),
    );
    await expectContract(
      'DELETE',
      '/session',
      401,
      token: '',
      headers: engine.browser(cookie),
    );
  });
}

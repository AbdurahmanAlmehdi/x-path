@Tags(['contract'])
library;

import 'dart:convert';

import 'package:test/test.dart';
import 'package:xp_api/testing.dart';
import 'package:xp_api/xp_api.dart';

import '../helpers/test_engine.dart';

/// Every response of the people endpoints and `GET /me` (ADR 0017) is
/// checked against `openapi.yaml`.
void main() {
  late OpenApiContract contract;
  late TestEngine engine;
  late String viewer;

  setUpAll(() async => contract = await OpenApiContract.load());
  setUp(() async {
    engine = await TestEngine.start();
    viewer = await engine.tokenFor(PersonRole.viewer);
  });
  tearDown(() => engine.close());

  Future<RawResponse> expectContract(
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
    return response;
  }

  test('request bodies match their schemas', () {
    expect(
      contract.validateSchema('CreatePersonRequest', {
        'name': 'Sam',
        'role': 'releaser',
      }),
      isEmpty,
    );
    expect(
      contract.validateSchema('CreatePersonRequest', {
        'name': 'Sam',
        'role': 'owner',
      }),
      isNotEmpty,
    );
    expect(
      contract.validateSchema('UpdatePersonRequest', {'role': 'admin'}),
      isEmpty,
    );
  });

  test('GET /me 200 and 401', () async {
    await expectContract('GET', '/me', 200);
    await expectContract('GET', '/me', 200, token: viewer);
    await expectContract('GET', '/me', 401, token: '');
  });

  test('GET and POST /people 200, 201, 400, 401, 403 and 409', () async {
    await expectContract('GET', '/people', 200, token: viewer);
    await expectContract('GET', '/people', 401, token: '');
    final created = await expectContract(
      'POST',
      '/people',
      201,
      body: {'name': 'Sam', 'role': 'developer'},
    );
    expect(created.json['id'], startsWith('per_'));
    await expectContract('POST', '/people', 400, body: {'name': 'Sam'});
    await expectContract(
      'POST',
      '/people',
      403,
      token: viewer,
      body: {'name': 'Kim', 'role': 'viewer'},
    );
    await expectContract(
      'POST',
      '/people',
      409,
      body: {'name': 'sam', 'role': 'viewer'},
    );
  });

  test('GET, PATCH and DELETE /people/{id}', () async {
    final sam =
        (await expectContract(
              'POST',
              '/people',
              201,
              body: {'name': 'Sam', 'role': 'developer'},
            )).json['id']!
            as String;
    final owner = '/people/${testOwner.id}';

    await expectContract('GET', '/people/$sam', 200, token: viewer);
    await expectContract('GET', '/people/per_nope', 404);
    await expectContract(
      'PATCH',
      '/people/$sam',
      200,
      body: {'role': 'releaser'},
    );
    await expectContract('PATCH', '/people/$sam', 400, body: {});
    await expectContract(
      'PATCH',
      '/people/$sam',
      403,
      token: viewer,
      body: {'role': 'admin'},
    );
    await expectContract('PATCH', owner, 409, body: {'role': 'viewer'});
    await expectContract('PATCH', '/people/per_nope', 404, body: {'name': 'x'});
    await expectContract('DELETE', owner, 409);
    await expectContract('DELETE', '/people/$sam', 403, token: viewer);
    await expectContract('DELETE', '/people/$sam', 204);
    await expectContract('DELETE', '/people/$sam', 404);
    final removed = await expectContract('GET', '/people/$sam', 200);
    expect(removed.json['removedAt'], isNotNull);
  });
}

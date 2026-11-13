import 'dart:convert';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';

import '../../helpers/test_engine.dart';

void main() {
  late TestEngine engine;
  late String cookie;

  setUp(() async {
    engine = await TestEngine.start();
    cookie = await engine.signInBrowser();
  });
  tearDown(() => engine.close());

  Future<RawResponse> addPerson(Map<String, String> headers) => engine.request(
    '/people',
    method: 'POST',
    token: '',
    headers: headers,
    body: jsonEncode({'name': 'Kim', 'role': 'viewer'}),
  );

  test('lets a cookie request that changes something through with the '
      'header and an Origin of the engine', () async {
    final response = await addPerson(engine.browser(cookie));

    expect(response.statusCode, 201, reason: response.body);
  });

  test('takes the public URL as an origin of the engine', () async {
    await engine.publicUrl.set('https://xpath.example.com');

    final response = await addPerson({
      ...engine.browser(cookie),
      'origin': 'https://xpath.example.com',
    });

    expect(response.statusCode, 201, reason: response.body);
  });

  test('refuses it with 403 csrf without X-XPath-CSRF', () async {
    for (final value in [null, '0']) {
      final headers = {...engine.browser(cookie)}..remove('x-xpath-csrf');
      if (value != null) headers['x-xpath-csrf'] = value;

      final response = await addPerson(headers);

      expect(response.statusCode, 403);
      expect(response.error['code'], 'csrf');
      expect(response.error['message'], contains('X-XPath-CSRF'));
    }
  });

  test('refuses it with 403 csrf from a foreign or absent Origin', () async {
    final foreign = await addPerson({
      ...engine.browser(cookie),
      'origin': 'http://evil.example',
    });
    final absent = await addPerson(
      {...engine.browser(cookie)}..remove('origin'),
    );
    final rebound = await addPerson({
      ...engine.browser(cookie),
      'host': 'evil.example:${engine.uri.port}',
    });

    for (final response in [foreign, absent, rebound]) {
      expect(response.statusCode, 403);
      expect(response.error['code'], 'csrf');
    }
    expect(await engine.people.list(), hasLength(1));
  });

  test('lets a cookie read without the header or an Origin', () async {
    final response = await engine.request(
      '/people',
      token: '',
      headers: {'cookie': cookie},
    );

    expect(response.statusCode, 200);
  });

  test('does not apply to a bearer request', () async {
    final response = await addPerson({'origin': 'http://evil.example'});
    final bearer = await engine.request(
      '/people',
      method: 'POST',
      headers: {'origin': 'http://evil.example', 'cookie': cookie},
      body: jsonEncode({'name': 'Lee', 'role': 'viewer'}),
    );

    expect(response.statusCode, 401, reason: 'no token, no cookie');
    expect(bearer.statusCode, 201);
    expect(
      ErrorResponse.fromJson(response.json).error.code,
      ApiErrorCode.unauthorized,
    );
  });
}

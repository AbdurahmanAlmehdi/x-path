import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xpd/xpd.dart';

Request _request(String path, {Map<String, String>? headers}) =>
    Request('GET', Uri.parse('http://localhost$path'), headers: headers);

void main() {
  group('runnerRefusalMiddleware', () {
    Future<List<String>> refusals(
      int status, {
      String path = '/runners/connect',
    }) async {
      final seen = <String>[];
      final handler = const Pipeline()
          .addMiddleware(
            runnerRefusalMiddleware((who, why) => seen.add('$who: $why')),
          )
          .addHandler((_) => Response(status));
      await handler(_request(path));
      return seen;
    }

    test('names why a runner connection was turned away', () async {
      expect(await refusals(401), [
        'an unknown address: an unknown or revoked credential (401)',
      ]);
      expect(await refusals(403), [
        'an unknown address: not a runner token (403)',
      ]);
      expect(await refusals(426), [
        'an unknown address: not a WebSocket upgrade (426)',
      ]);
    });

    test('says nothing about other answers and other routes', () async {
      expect(await refusals(200), isEmpty);
      expect(await refusals(401, path: '/projects'), isEmpty);
    });
  });

  group('errorMiddleware', () {
    test('lets a response through', () async {
      final handler = const Pipeline()
          .addMiddleware(errorMiddleware())
          .addHandler((_) => Response.ok('fine'));

      final response = await handler(_request('/'));

      expect(response.statusCode, 200);
    });

    test('turns a thrown error into a generic 500 and reports it', () async {
      final seen = <Object>[];
      final handler = const Pipeline()
          .addMiddleware(errorMiddleware(onError: (e, _) => seen.add(e)))
          .addHandler((_) => throw StateError('secret detail'));

      final response = await handler(_request('/'));

      expect(response.statusCode, 500);
      final body = await response.readAsString();
      expect(body, isNot(contains('secret detail')));
      expect(
        ErrorResponse.fromJson(jsonDecode(body) as Map<String, dynamic>)
            .error
            .code,
        ApiErrorCode.internal,
      );
      expect(seen, [isA<StateError>()]);
    });

    test('works without an error listener', () async {
      final handler = const Pipeline()
          .addMiddleware(errorMiddleware())
          .addHandler((_) => throw StateError('x'));

      expect((await handler(_request('/'))).statusCode, 500);
    });

    test('lets a hijack through: the socket is no longer ours', () {
      final handler = const Pipeline()
          .addMiddleware(errorMiddleware(onError: (e, _) => fail('reported')))
          .addHandler((_) => throw const HijackException());

      expect(handler(_request('/')), throwsA(isA<HijackException>()));
    });
  });

  group('authMiddleware', () {
    late TokenService tokens;
    late String secret;
    late Handler handler;

    setUp(() async {
      tokens = TokenService(
        tokens: InMemoryDeviceTokenRepository(),
        clock: const SystemClock(),
      );
      secret = (await tokens.issue(
        name: 'n',
        kind: DeviceTokenKind.app,
      )).secret;
      handler = const Pipeline()
          .addMiddleware(authMiddleware(tokens, publicPaths: {'/open'}))
          .addHandler((_) => Response.ok('in'));
    });

    test('lets a valid bearer token through', () async {
      final response = await handler(
        _request('/closed', headers: {'authorization': 'Bearer $secret'}),
      );

      expect(response.statusCode, 200);
    });

    test('hands the token to the handler, whatever its kind', () async {
      for (final kind in DeviceTokenKind.values) {
        final issued = await tokens.issue(name: 'dev $kind', kind: kind);
        DeviceToken? seen;
        final reading = const Pipeline()
            .addMiddleware(authMiddleware(tokens))
            .addHandler((request) {
              seen = deviceTokenOf(request);
              return Response.ok('in');
            });

        await reading(
          _request(
            '/closed',
            headers: {'authorization': 'Bearer ${issued.secret}'},
          ),
        );

        expect(seen, issued.token, reason: kind.name);
        expect(seen!.kind, kind);
      }
    });

    test('lets public paths through without a token', () async {
      expect((await handler(_request('/open'))).statusCode, 200);
    });

    test('refuses everything else with 401 and a challenge', () async {
      for (final headers in <Map<String, String>>[
        {},
        {'authorization': secret},
        {'authorization': 'Bearer'},
        {'authorization': 'Bearer a b'},
        {'authorization': 'Token $secret'},
        {'authorization': 'Bearer ${secret}x'},
      ]) {
        final response = await handler(_request('/closed', headers: headers));

        expect(response.statusCode, 401, reason: '$headers');
        expect(response.headers['www-authenticate'], 'Bearer');
      }
    });
  });

  group('responses', () {
    test('jsonResponse encodes the body as JSON', () async {
      final response = jsonResponse({'a': 1}, statusCode: 201);

      expect(response.statusCode, 201);
      expect(response.headers['content-type'], 'application/json');
      expect(await response.readAsString(), '{"a":1}');
    });

    test('jsonResponse adds the headers it is given', () {
      final response = jsonResponse(
        {'a': 1},
        headers: {'location': '/projects/p'},
      );

      expect(response.headers['location'], '/projects/p');
      expect(response.headers['content-type'], 'application/json');
    });

    test(
      'errorResponse uses the status of the code and adds headers',
      () async {
        final response = errorResponse(
          ApiErrorCode.notFound,
          'gone',
          headers: {'x-extra': 'yes'},
        );

        expect(response.statusCode, 404);
        expect(response.headers['x-extra'], 'yes');
        expect(response.headers['content-type'], 'application/json');
        expect(
          await response.readAsString(),
          '{"error":{"code":"not_found","message":"gone"}}',
        );
      },
    );
  });
}

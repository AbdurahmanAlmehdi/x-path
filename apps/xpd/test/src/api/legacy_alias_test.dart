import 'dart:io';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xpd/xpd.dart';

import '../../helpers/test_engine.dart';

void main() {
  late TestEngine engine;

  setUp(() async {
    engine = await TestEngine.start();
    engine.folders['/work/app'] = projectFiles;
  });
  tearDown(() => engine.close());

  String errorMessage(RawResponse response) =>
      ErrorResponse.fromJson(response.json).error.message;

  group('under /api/v1', () {
    test('serves the API, not deprecated', () async {
      final response = await engine.request('/projects');

      expect(response.statusCode, 200);
      expect(response.headers, isNot(contains('deprecation')));
      expect(response.headers, isNot(contains('sunset')));
    });

    test('needs a token like any route of the API', () async {
      final response = await engine.request('/projects', token: '');

      expect(response.statusCode, 401);
    });

    test('answers a path no route has with the JSON 404', () async {
      for (final path in ['/nope', '']) {
        final response = await engine.request(path);

        expect(response.statusCode, 404, reason: path);
        expect(response.contentType, startsWith('application/json'));
      }
    });

    test('puts the Location of what it made under /api/v1', () async {
      final response = await engine.request(
        '/projects',
        method: 'POST',
        body: '{"path": "/work/app"}',
      );

      expect(response.statusCode, 201, reason: response.body);
      expect(
        response.headers['location'],
        '/api/v1/projects/${response.json['id']}',
      );
    });
  });

  group('a root path', () {
    test('with a bearer token is the API, deprecated', () async {
      final mounted = await engine.request('/projects');
      final alias = await engine.request('/projects', root: true);

      expect(alias.statusCode, 200);
      expect(alias.body, mounted.body);
      expect(alias.headers['deprecation'], 'true');
      expect(alias.headers['sunset'], HttpDate.format(legacySunset));
      expect(
        alias.headers['link'],
        '</api/v1/projects>; rel="successor-version"',
      );
      expect(alias.headers['vary'], 'Authorization');
    });

    test('with a token the engine refuses still gets the API 401', () async {
      final response = await engine.request(
        '/projects',
        token: 'xpt_nope',
        root: true,
      );

      expect(response.statusCode, 401);
      expect(response.headers['deprecation'], 'true');
    });

    test('keeps the Location of what it made at the root', () async {
      final response = await engine.request(
        '/projects',
        method: 'POST',
        body: '{"path": "/work/app"}',
        root: true,
      );

      expect(response.statusCode, 201, reason: response.body);
      expect(response.headers['location'], '/projects/${response.json['id']}');
    });

    test('without Authorization is not the API', () async {
      for (final method in ['GET', 'POST']) {
        final response = await engine.request(
          '/projects',
          method: method,
          token: '',
          root: true,
        );

        expect(response.statusCode, 404, reason: method);
        expect(
          errorMessage(response),
          'Nothing is served at /projects. The API is under /api/v1.',
        );
        expect(response.headers['vary'], 'Authorization');
        expect(response.headers, isNot(contains('deprecation')));
      }
    });

    test('that is public is the API without a token', () async {
      for (final path in publicPaths.difference({'/runners/pair'})) {
        final response = await engine.request(path, token: '', root: true);

        expect(response.statusCode, 200, reason: path);
        expect(response.headers['deprecation'], 'true', reason: path);
      }
    });

    test('lets a runner made before /api/v1 pair and connect', () async {
      final owner = (await engine.tokens.authenticate(engine.secret))!;
      final pairing = await engine.runnerService.createPairingToken(
        name: 'old-runner',
        by: owner,
      );

      final paired = await engine.request(
        '/runners/pair',
        method: 'POST',
        token: '',
        body: '{"pairingToken": "${pairing.token}"}',
        root: true,
      );
      expect(paired.statusCode, 201, reason: paired.body);
      expect(paired.headers['deprecation'], 'true');
      final stream = await engine.connectRunner(
        token: PairRunnerResponse.fromJson(paired.json).token,
        root: true,
      );
      addTearDown(stream.close);

      expect(await stream.next(), isA<WelcomeFrame>());
    });

    test('only matches /api/v1 as a whole segment', () async {
      final response = await engine.request(
        '/api/v1x/projects',
        token: '',
        root: true,
      );

      expect(response.statusCode, 404);
      expect(response.headers['vary'], 'Authorization');
    });
  });
}

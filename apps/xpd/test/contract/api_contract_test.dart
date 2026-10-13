@Tags(['contract'])
library;

import 'dart:convert';

import 'package:test/test.dart';
import 'package:xp_api/testing.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../helpers/test_engine.dart';

/// Every response the engine gives is checked against `openapi.yaml`.
void main() {
  late OpenApiContract contract;
  late TestEngine engine;

  setUpAll(() async => contract = await OpenApiContract.load());
  setUp(() async => engine = await TestEngine.start());
  tearDown(() => engine.close());

  void expectContract(
    RawResponse response, {
    required String path,
    String method = 'GET',
  }) => contract.expectResponse(
    method: method,
    path: path,
    statusCode: response.statusCode,
    contentType: response.contentType,
    body: response.body,
  );

  test('GET /health', () async {
    final response = await engine.request('/health', token: '');

    expect(response.statusCode, 200);
    expectContract(response, path: '/health');
  });

  test('GET /version', () async {
    final response = await engine.request('/version', token: '');

    expect(response.statusCode, 200);
    expectContract(response, path: '/version');
  });

  group('GET /events', () {
    test('401 without a token', () async {
      final response = await engine.handshake('/events', token: '');

      expect(response.statusCode, 401);
      expectContract(response, path: '/events');
    });

    test('401 with an unknown token', () async {
      final response = await engine.handshake('/events', token: 'xpt_nope');

      expect(response.statusCode, 401);
      expectContract(response, path: '/events');
    });

    test('400 for a bad cursor', () async {
      final response = await engine.handshake('/events?after=-3');

      expect(response.statusCode, 400);
      expectContract(response, path: '/events');
    });

    test('409 for a cursor outside the window', () async {
      final response = await engine.handshake('/events?after=50');

      expect(response.statusCode, 409);
      expectContract(response, path: '/events');
    });

    test('426 for a plain request', () async {
      final response = await engine.request('/events');

      expect(response.statusCode, 426);
      expectContract(response, path: '/events');
    });

    test('101 and frames that match SequencedEvent', () async {
      final stream = await engine.connect(after: 0);
      addTearDown(stream.close);

      // Connecting succeeded, so the engine answered 101.
      contract.expectResponse(
        method: 'GET',
        path: '/events',
        statusCode: 101,
        body: '',
      );
      for (final frame in await stream.take(2)) {
        expect(
          contract.validateSchema('SequencedEvent', frame.toJson()),
          isEmpty,
        );
      }
    });
  });

  test('500 matches the error envelope', () async {
    final broken = await TestEngine.start(
      repository: ThrowingDeviceTokenRepository(),
    );
    addTearDown(broken.close);

    final failing = await broken.request('/events');

    expect(failing.statusCode, 500);
    expectContract(failing, path: '/events');
  });

  test('an unknown route answers in the error envelope', () async {
    final response = await engine.request('/nope');

    expect(response.statusCode, 404);
    expect(contract.validateSchema('ErrorResponse', response.json), isEmpty);
    expect(
      ErrorResponse.fromJson(response.json).error.code,
      ApiErrorCode.notFound,
    );
  });

  group('projects', () {
    Future<RawResponse> send(String method, String path, [Object? body]) =>
        engine.request(
          path,
          method: method,
          body: body == null ? null : jsonEncode(body),
        );

    Future<String> addProject() async {
      engine.folders['/work/app'] = projectFiles;
      final response = await send('POST', '/projects', {'path': '/work/app'});
      return response.json['id']! as String;
    }

    test('request bodies match their schemas', () {
      for (final (schema, body) in <(String, Object)>[
        ('AddProjectRequest', {'path': '/work/app'}),
        ('AddProjectRequest', {'remote': 'octo/app'}),
        (
          'ProfileEdits',
          {
            'defaultBaseBranch': 'dev',
            'apps': [
              {
                'path': '.',
                'storeCountry': 'ly',
                'flavors': [
                  {
                    'name': 'prod',
                    'prod': true,
                    'shorebird': true,
                    'entrypoint': 'lib/main_prod.dart',
                    'iosBundleId': 'com.example',
                    'androidAppId': 'com.example',
                    'versionFiles': ['pubspec.yaml'],
                  },
                ],
              },
            ],
          },
        ),
      ]) {
        expect(contract.validateSchema(schema, body), isEmpty, reason: schema);
      }
      expect(
        contract.validateSchema('AddProjectRequest', {
          'path': '/a',
          'remote': 'b/c',
        }),
        isNotEmpty,
      );
    });

    test('POST /projects by path', () async {
      engine.folders['/work/app'] = projectFiles;

      final response = await send('POST', '/projects', {'path': '/work/app'});

      expect(response.statusCode, 201);
      expectContract(response, path: '/projects', method: 'POST');
    });

    test('POST /projects by remote', () async {
      final response = await send('POST', '/projects', {'remote': 'octo/app'});

      expect(response.statusCode, 201);
      expectContract(response, path: '/projects', method: 'POST');
    });

    test('POST /projects 400 for a body that is not a request', () async {
      final response = await send('POST', '/projects', {'path': 3});

      expect(response.statusCode, 400);
      expectContract(response, path: '/projects', method: 'POST');
    });

    test('POST /projects 401 without a token', () async {
      final response = await engine.request(
        '/projects',
        method: 'POST',
        token: '',
        body: '{}',
      );

      expect(response.statusCode, 401);
      expectContract(response, path: '/projects', method: 'POST');
    });

    test('POST /projects 404 for a repository GitHub does not know', () async {
      final response = await send('POST', '/projects', {'remote': 'octo/gone'});

      expect(response.statusCode, 404);
      expectContract(response, path: '/projects', method: 'POST');
    });

    test('POST /projects 409 for a repository that is a project', () async {
      await addProject();

      final response = await send('POST', '/projects', {'remote': 'octo/app'});

      expect(response.statusCode, 409);
      expectContract(response, path: '/projects', method: 'POST');
    });

    test('POST /projects 502 when GitHub refuses', () async {
      engine.github.failure = const GitHubAuthException('Bad credentials');

      final response = await send('POST', '/projects', {'remote': 'octo/app'});

      expect(response.statusCode, 502);
      expectContract(response, path: '/projects', method: 'POST');
    });

    test('POST /projects 503 while the secrets are locked', () async {
      engine.github.failure = const SecretsLockedException('locked');

      final response = await send('POST', '/projects', {'remote': 'octo/app'});

      expect(response.statusCode, 503);
      expectContract(response, path: '/projects', method: 'POST');
    });

    test('GET /projects', () async {
      await addProject();

      final response = await send('GET', '/projects');

      expect(response.statusCode, 200);
      expect(response.json['projects']! as List, hasLength(1));
      expectContract(response, path: '/projects');
    });

    test('GET /projects with none', () async {
      final response = await send('GET', '/projects');

      expect(response.json['projects'], isEmpty);
      expectContract(response, path: '/projects');
    });

    test('GET /projects/{id}', () async {
      final id = await addProject();

      final response = await send('GET', '/projects/$id');

      expect(response.statusCode, 200);
      expectContract(response, path: '/projects/$id');
    });

    test('GET /projects/{id} 404', () async {
      final response = await send('GET', '/projects/prj_nope');

      expect(response.statusCode, 404);
      expectContract(response, path: '/projects/prj_nope');
    });

    test('POST /projects/{id}/scan', () async {
      final id = await addProject();

      final response = await send('POST', '/projects/$id/scan');

      expect(response.statusCode, 200);
      expectContract(response, path: '/projects/$id/scan', method: 'POST');
    });

    test('POST /projects/{id}/scan 404', () async {
      final response = await send('POST', '/projects/prj_nope/scan');

      expect(response.statusCode, 404);
      expectContract(response, path: '/projects/prj_nope/scan', method: 'POST');
    });

    test('POST /projects/{id}/scan 502 when git cannot fetch', () async {
      final id = await addProject();
      engine.folders.remove('/work/app');
      engine.git.fetchFailure = const GitException('network down');

      final response = await send('POST', '/projects/$id/scan');

      expect(response.statusCode, 502);
      expectContract(response, path: '/projects/$id/scan', method: 'POST');
    });

    test('PATCH /projects/{id}', () async {
      final id = await addProject();

      final response = await send('PATCH', '/projects/$id', {
        'defaultBaseBranch': 'dev',
        'apps': [
          {'path': '.', 'storeCountry': 'LY'},
        ],
      });

      expect(response.statusCode, 200);
      expect(response.json['defaultBaseBranch'], 'dev');
      expectContract(response, path: '/projects/$id', method: 'PATCH');
    });

    test('PATCH /projects/{id} 400 for an edit of something missing', () async {
      final id = await addProject();

      final response = await send('PATCH', '/projects/$id', {
        'apps': [
          {'path': 'apps/nope'},
        ],
      });

      expect(response.statusCode, 400);
      expectContract(response, path: '/projects/$id', method: 'PATCH');
    });

    test('PATCH /projects/{id} 404', () async {
      final response = await send('PATCH', '/projects/prj_nope', {});

      expect(response.statusCode, 404);
      expectContract(response, path: '/projects/prj_nope', method: 'PATCH');
    });

    test('DELETE /projects/{id}', () async {
      final id = await addProject();

      final response = await send('DELETE', '/projects/$id');

      expect(response.statusCode, 204);
      expectContract(response, path: '/projects/$id', method: 'DELETE');
    });

    test('DELETE /projects/{id} 404', () async {
      final response = await send('DELETE', '/projects/prj_nope');

      expect(response.statusCode, 404);
      expectContract(response, path: '/projects/prj_nope', method: 'DELETE');
    });

    test('every project response is a Project', () async {
      final id = await addProject();

      final response = await send('GET', '/projects/$id');

      expect(contract.validateSchema('Project', response.json), isEmpty);
      expect(Project.fromJson(response.json).id, id);
    });
  });
}

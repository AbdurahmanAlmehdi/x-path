@Tags(['contract'])
library;

import 'dart:convert';

import 'package:test/test.dart';
import 'package:xp_api/testing.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xp_fake_asc/xp_fake_asc.dart';

import '../helpers/test_engine.dart';
import '../helpers/test_run_fakes.dart';

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
        ('AddProjectRequest', {'remote': 'git@bitbucket.org:ws/app.git'}),
        (
          'AddProjectRequest',
          {'path': '/work/app', 'sshUrl': 'git@bitbucket.org:ws/app.git'},
        ),
        (
          'ProfileEdits',
          {
            'defaultBaseBranch': 'dev',
            'apps': [
              {
                'path': '.',
                'storeCountry': 'ly',
                'iosLinux': false,
                'flavors': [
                  {
                    'name': 'prod',
                    'prod': true,
                    'shorebird': true,
                    'entrypoint': 'lib/main_prod.dart',
                    'iosBundleId': 'com.example',
                    'androidAppId': 'com.example',
                    'versionFiles': ['pubspec.yaml'],
                    'firebaseAppId': {
                      'android': '1:123456789012:android:abcdef',
                      'ios': '',
                    },
                    'appleAppId': '1234567890',
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
      expect(
        contract.validateSchema('AddProjectRequest', {
          'remote': 'b/c',
          'sshUrl': 'git@h:b/c.git',
        }),
        isNotEmpty,
        reason: 'sshUrl goes with path only',
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

    test('POST /projects from another host, by its SSH URL', () async {
      final response = await send('POST', '/projects', {
        'remote': 'git@bitbucket.org:ws/app.git',
      });

      expect(response.statusCode, 201);
      expectContract(response, path: '/projects', method: 'POST');
      expect(response.json.containsKey('githubRepoId'), isFalse);
    });

    test('POST /projects 422 offers the SSH URL of an HTTPS origin', () async {
      final response = await send('POST', '/projects', {
        'remote': 'https://bitbucket.org/ws/app.git',
      });

      expect(response.statusCode, 422);
      expectContract(response, path: '/projects', method: 'POST');
      expect(response.json['sshUrl'], 'git@bitbucket.org:ws/app.git');
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

    test("POST /projects/{id}/scan with a flavor's own Linux iOS "
        'limits', () async {
      engine.folders['/work/icons'] = {
        ...projectFiles,
        'ios/Runner.xcodeproj/project.pbxproj': '''
{
  objects = {
    T = {
      isa = PBXNativeTarget;
      buildConfigurationList = L;
      buildPhases = ( P );
      name = Runner;
      productType = "com.apple.product-type.application";
    };
    P = { isa = PBXResourcesBuildPhase; files = ( B ); };
    B = { isa = PBXBuildFile; fileRef = F; };
    F = {
      isa = PBXFileReference;
      path = Runner/Assets.xcassets;
      sourceTree = SOURCE_ROOT;
    };
    L = { isa = XCConfigurationList; buildConfigurations = ( C ); };
    C = {
      isa = XCBuildConfiguration;
      buildSettings = {
        ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
        PRODUCT_BUNDLE_IDENTIFIER = com.example;
      };
      name = Release;
    };
    R = { isa = PBXProject; buildConfigurationList = L; targets = ( T ); };
  };
  rootObject = R;
}
''',
        'ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json':
            '{"images": [{"idiom": "iphone", "size": "60x60"}]}',
      };
      final added = await send('POST', '/projects', {'path': '/work/icons'});
      final id = added.json['id']! as String;

      final response = await send('POST', '/projects/$id/scan');

      expect(response.statusCode, 200);
      expectContract(response, path: '/projects/$id/scan', method: 'POST');
      final app = ((response.json['profile'] as Map)['apps'] as List).single;
      expect(
        (((app as Map)['flavors'] as List).single as Map)['iosLinuxLimits'],
        [contains('the app icon set AppIcon, which has several sizes')],
      );
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

    test('PATCH /projects/{id} sets the store ids of a flavor', () async {
      final id = await addProject();

      final response = await send('PATCH', '/projects/$id', {
        'apps': [
          {
            'path': '.',
            'flavors': [
              {
                'name': 'default',
                'firebaseAppId': {'android': '1:123456789012:android:abcdef'},
                'appleAppId': '1234567890',
              },
            ],
          },
        ],
      });

      expect(response.statusCode, 200);
      final flavor =
          (((response.json['profile'] as Map)['apps'] as List).single
                  as Map)['flavors']
              as List;
      expect((flavor.single as Map)['firebaseAppId'], {
        'android': '1:123456789012:android:abcdef',
      });
      expect((flavor.single as Map)['appleAppId'], '1234567890');
      expectContract(response, path: '/projects/$id', method: 'PATCH');
    });

    test('PATCH /projects/{id} turns Linux iOS builds off and on for an '
        'app', () async {
      final id = await addProject();
      Future<Map<String, Object?>> turn({required bool on}) async {
        final response = await send('PATCH', '/projects/$id', {
          'apps': [
            {'path': '.', 'iosLinux': on},
          ],
        });
        expect(response.statusCode, 200);
        expectContract(response, path: '/projects/$id', method: 'PATCH');
        return ((response.json['profile'] as Map)['apps'] as List).single
            as Map<String, Object?>;
      }

      expect((await turn(on: false))['iosLinux'], isFalse);
      final read = await send('GET', '/projects/$id');
      expect(
        (((read.json['profile'] as Map)['apps'] as List).single
            as Map)['iosLinux'],
        isFalse,
      );
      expect(await turn(on: true), isNot(contains('iosLinux')));
    });

    test('PATCH /projects/{id} 400 for a store id of the wrong form', () async {
      final id = await addProject();

      final response = await send('PATCH', '/projects/$id', {
        'apps': [
          {
            'path': '.',
            'flavors': [
              {
                'name': 'default',
                'firebaseAppId': {'android': '1:1:ios:a'},
              },
            ],
          },
        ],
      });

      expect(response.statusCode, 400);
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

  group('artifacts', () {
    Future<RawResponse> send(String method, String path) =>
        engine.request(path, method: method);

    Future<(Job, ArtifactRecord)> jobWithApk() async {
      final job = await engine.createJob(['x']);
      return (job, await engine.addArtifact(job.id));
    }

    test('GET /jobs/{id}/artifacts', () async {
      final (job, apk) = await jobWithApk();
      await engine.addArtifact(
        job.id,
        name: 'manifest.json',
        kind: ArtifactKind.manifest,
        content: '{}',
      );

      final response = await send('GET', '/jobs/${job.id}/artifacts');

      expect(response.statusCode, 200);
      expect(response.json['artifacts']! as List, hasLength(2));
      expectContract(response, path: '/jobs/${job.id}/artifacts');
      expect(
        contract.validateSchema('Artifact', apk.toArtifact().toJson()),
        isEmpty,
      );
    });

    test('GET /jobs/{id}/artifacts for a job without any', () async {
      final job = await engine.createJob(['x']);

      final response = await send('GET', '/jobs/${job.id}/artifacts');

      expectContract(response, path: '/jobs/${job.id}/artifacts');
    });

    test('GET /jobs/{id}/artifacts 401 and 404', () async {
      final unauthorized = await engine.request(
        '/jobs/job_x/artifacts',
        token: '',
      );
      final missing = await send('GET', '/jobs/job_nope/artifacts');

      expect((unauthorized.statusCode, missing.statusCode), (401, 404));
      expectContract(unauthorized, path: '/jobs/job_x/artifacts');
      expectContract(missing, path: '/jobs/job_nope/artifacts');
    });

    test('GET /artifacts/{id}', () async {
      final (_, apk) = await jobWithApk();

      final response = await send('GET', '/artifacts/${apk.id}');

      expect(response.statusCode, 200);
      expectContract(response, path: '/artifacts/${apk.id}');
    });

    test('GET /artifacts/{id} 401 and 404', () async {
      final unauthorized = await engine.request('/artifacts/art_x', token: '');
      final missing = await send('GET', '/artifacts/art_nope');

      expect((unauthorized.statusCode, missing.statusCode), (401, 404));
      expectContract(unauthorized, path: '/artifacts/art_x');
      expectContract(missing, path: '/artifacts/art_nope');
    });

    test('GET /artifacts/{id}/download', () async {
      final (_, apk) = await jobWithApk();

      final response = await engine.download('/artifacts/${apk.id}/download');

      expect(response.statusCode, 200);
      expect(response.headers.contentLength, apk.size);
      expect(response.headers.value('x-content-sha256'), apk.sha256);
      contract.expectResponse(
        method: 'GET',
        path: '/artifacts/${apk.id}/download',
        statusCode: response.statusCode,
        contentType: response.headers.contentType?.toString(),
        body: response.text,
      );
    });

    test('GET /artifacts/{id}/download 401 and 404', () async {
      final unauthorized = await engine.request(
        '/artifacts/art_x/download',
        token: '',
      );
      final missing = await send('GET', '/artifacts/art_nope/download');

      expect((unauthorized.statusCode, missing.statusCode), (401, 404));
      expectContract(unauthorized, path: '/artifacts/art_x/download');
      expectContract(missing, path: '/artifacts/art_nope/download');
    });

    for (final action in ['pin', 'unpin']) {
      test('POST /artifacts/{id}/$action', () async {
        final (_, apk) = await jobWithApk();

        final response = await send('POST', '/artifacts/${apk.id}/$action');

        expect(response.statusCode, 200);
        expect(Artifact.fromJson(response.json).pinned, action == 'pin');
        expectContract(
          response,
          path: '/artifacts/${apk.id}/$action',
          method: 'POST',
        );
      });

      test('POST /artifacts/{id}/$action 401 and 404', () async {
        final unauthorized = await engine.request(
          '/artifacts/art_x/$action',
          method: 'POST',
          token: '',
        );
        final missing = await send('POST', '/artifacts/art_nope/$action');

        expect((unauthorized.statusCode, missing.statusCode), (401, 404));
        expectContract(
          unauthorized,
          path: '/artifacts/art_x/$action',
          method: 'POST',
        );
        expectContract(
          missing,
          path: '/artifacts/art_nope/$action',
          method: 'POST',
        );
      });
    }
  });

  group('tests', () {
    Future<RawResponse> send(String path) => engine.request(path);

    test('GET /jobs/{id}/tests', () async {
      final job = await engine.createJob(['x']);
      await engine.testRuns.save(sampleTestRun(job.id, baseline: true));

      final response = await send('/jobs/${job.id}/tests');

      expect(response.statusCode, 200);
      expectContract(response, path: '/jobs/${job.id}/tests');
      expect(
        TestRunResponse.fromJson(response.json).run.diff.newFailures,
        hasLength(1),
      );
    });

    test('GET /jobs/{id}/tests with every status and a page', () async {
      final job = await engine.createJob(['x']);
      await engine.testRuns.save(sampleTestRun(job.id));

      final response = await send(
        '/jobs/${job.id}/tests?status=passed,failed,errored,skipped&limit=3',
      );

      expect(response.statusCode, 200);
      expect(response.json['tests']! as List, hasLength(3));
      expectContract(response, path: '/jobs/${job.id}/tests');
    });

    test('GET /jobs/{id}/tests 400, 401 and 404', () async {
      final job = await engine.createJob(['x']);
      final invalid = await send('/jobs/${job.id}/tests?limit=0');
      final unauthorized = await engine.request('/jobs/job_x/tests', token: '');
      final missing = await send('/jobs/job_nope/tests');
      final noRun = await send('/jobs/${job.id}/tests');

      expect([invalid, unauthorized, missing, noRun].map((r) => r.statusCode), [
        400,
        401,
        404,
        404,
      ]);
      expectContract(invalid, path: '/jobs/${job.id}/tests');
      expectContract(unauthorized, path: '/jobs/job_x/tests');
      expectContract(missing, path: '/jobs/job_nope/tests');
      expectContract(noRun, path: '/jobs/${job.id}/tests');
    });

    test('GET /projects/{id}/tests/baseline', () async {
      await engine.projectRepository.add(testRunProject());
      final job = await engine.createJob(['x']);
      await engine.testRuns.save(sampleTestRun(job.id, baseline: true));

      final response = await send('/projects/prj_1/tests/baseline');

      expect(response.statusCode, 200);
      expect(response.json['baselines']! as List, hasLength(1));
      expectContract(response, path: '/projects/prj_1/tests/baseline');
    });

    test('GET /projects/{id}/tests/baseline without a baseline', () async {
      await engine.projectRepository.add(testRunProject());

      final response = await send('/projects/prj_1/tests/baseline');

      expect(response.json, {'baselines': <Object?>[]});
      expectContract(response, path: '/projects/prj_1/tests/baseline');
    });

    test('GET /projects/{id}/tests/baseline 401 and 404', () async {
      final unauthorized = await engine.request(
        '/projects/prj_x/tests/baseline',
        token: '',
      );
      final missing = await send('/projects/prj_nope/tests/baseline');

      expect((unauthorized.statusCode, missing.statusCode), (401, 404));
      expectContract(unauthorized, path: '/projects/prj_x/tests/baseline');
      expectContract(missing, path: '/projects/prj_nope/tests/baseline');
    });
  });

  group('credentials', () {
    late String projectId;
    late String mcp;

    Future<RawResponse> send(
      String method,
      String path, {
      Object? body,
      String? token,
    }) => engine.request(
      path,
      method: method,
      token: token,
      body: body == null ? null : jsonEncode(body),
    );

    Future<RawResponse> check(
      String method,
      String path,
      String template, {
      Object? body,
      String? token,
    }) async {
      final response = await send(method, path, body: body, token: token);
      expectContract(response, path: template, method: method);
      return response;
    }

    Map<String, Object?> shorebird([String name = 'Studio']) => {
      'name': name,
      'kind': 'shorebird',
      'token': 'sb_api_x',
    };

    Future<String> create([String name = 'Studio']) async =>
        (await send('POST', '/credentials', body: shorebird(name))).json['id']!
            as String;

    String assignPath([String flavor = 'default']) =>
        '/projects/$projectId/flavors/$flavor/credentials/shorebird';

    setUp(() async {
      engine.folders['/work/app'] = projectFiles;
      final added = await engine.request(
        '/projects',
        method: 'POST',
        body: jsonEncode({'path': '/work/app'}),
      );
      projectId = added.json['id']! as String;
      engine.credentialRepository.flavors.add(
        CredentialFlavor(
          id: 'flv_1',
          projectId: projectId,
          projectName: 'acme/app',
          appPath: '.',
          name: 'default',
        ),
      );
      mcp = (await engine.tokens.issue(
        name: 'agent',
        kind: DeviceTokenKind.mcp,
      )).secret;
    });

    test('POST /credentials 201, 400, 403, 409, 422, 502, 503', () async {
      const template = '/credentials';
      final created = await check(
        'POST',
        template,
        template,
        body: shorebird(),
      );
      expect(created.statusCode, 201);
      for (final (status, body, token) in [
        (400, <String, Object?>{'name': 'x', 'kind': 'github'}, null),
        (403, shorebird('Other'), mcp),
        (409, shorebird('STUDIO'), null),
      ]) {
        final response = await check(
          'POST',
          template,
          template,
          body: body,
          token: token,
        );
        expect(response.statusCode, status);
      }
      engine.credentialVerifiers[CredentialKind.shorebird]!.answers.addAll([
        const VerificationResult.rejected('No.'),
        const VerificationResult.unreachable('Down.'),
      ]);
      expect(
        (await check(
          'POST',
          template,
          template,
          body: shorebird('A'),
        )).statusCode,
        422,
      );
      expect(
        (await check(
          'POST',
          template,
          template,
          body: shorebird('B'),
        )).statusCode,
        502,
      );
      engine.credentialSecrets.failure = const SecretsLockedException('l');
      expect(
        (await check(
          'POST',
          template,
          template,
          body: shorebird('C'),
        )).statusCode,
        503,
      );
    });

    test('POST /credentials takes a dart-define file, 201 and 422, and never '
        'repeats it', () async {
      const template = '/credentials';
      final created = await check(
        'POST',
        template,
        template,
        body: {
          'name': 'Prod defines',
          'kind': 'dart_defines',
          'dartDefines': '{"API_KEY": "s3cret-value"}',
        },
      );
      final refused = await check(
        'POST',
        template,
        template,
        body: {
          'name': 'Broken',
          'kind': 'dart_defines',
          'dartDefines': '{"API_KEY": {"s3cret-value": 1}}',
        },
      );

      expect(created.statusCode, 201);
      expect(created.json['kind'], 'dart_defines');
      expect(created.json['status'], 'verified');
      final replaced = await check(
        'PUT',
        '/credentials/${created.json['id']}',
        '/credentials/{credentialId}',
        body: {'dartDefines': 'API_KEY=s3cret-value'},
      );
      expect(refused.statusCode, 422);
      expect(replaced.statusCode, 200);
      expect(jsonEncode(replaced.json), isNot(contains('s3cret-value')));
      expect(jsonEncode(created.json), isNot(contains('s3cret-value')));
      expect(jsonEncode(refused.json), isNot(contains('s3cret-value')));
    });

    test('POST /credentials takes an Apple Distribution identity, 201 and '
        '422', () async {
      const template = '/credentials';
      Map<String, Object?> identity(String name, String certificate) => {
        'name': name,
        'kind': 'apple_distribution',
        'privateKey':
            '-----BEGIN PRIVATE KEY-----\nMIIE\n-----END PRIVATE KEY-----\n',
        'certificate': certificate,
      };

      final created = await check(
        'POST',
        template,
        template,
        body: identity('Linux signing', fakeDistributionCertificate),
      );
      final refused = await check(
        'POST',
        template,
        template,
        body: identity('Broken', 'bm90IGEgY2VydGlmaWNhdGU='),
      );

      expect(created.statusCode, 201);
      expect(created.json['kind'], 'apple_distribution');
      expect(
        created.json['account'],
        'Apple Distribution: XPath Test (TEAM123456)',
      );
      expect(created.body, isNot(contains('PRIVATE KEY')));
      expect(refused.statusCode, 422);
    });

    test('POST /projects/{id}/flavors/{flavor}/distribution-certificate 201, '
        '400, 403, 404, 409', () async {
      const template =
          '/projects/{id}/flavors/{flavor}/distribution-certificate';
      String path([String flavor = 'default']) =>
          '/projects/$projectId/flavors/$flavor/distribution-certificate';
      engine.appStoreConnect.createdContent = base64.decode(
        fakeDistributionCertificate,
      );

      final noKey = await check('POST', path(), template, body: {'name': 'A'});
      final key = await send(
        'POST',
        '/credentials',
        body: {
          'name': 'ASC',
          'kind': 'asc_key',
          'keyId': fakeAscKeyId,
          'issuerId': fakeAscIssuerId,
          'privateKey': fakeAscPrivateKeyPem,
        },
      );
      await send(
        'PUT',
        '/projects/$projectId/flavors/default/credentials/asc_key',
        body: {'credentialId': key.json['id']},
      );
      final created = await check(
        'POST',
        path(),
        template,
        body: {'name': 'Linux signing'},
      );
      final statuses = [
        for (final (flavor, body, token) in [
          ('default', <String, Object?>{'name': ''}, null),
          ('default', <String, Object?>{'name': 'B'}, mcp),
          ('nope', <String, Object?>{'name': 'B'}, null),
          ('default', <String, Object?>{'name': 'linux SIGNING'}, null),
        ])
          (await check(
            'POST',
            path(flavor),
            template,
            body: body,
            token: token,
          )).statusCode,
      ];
      engine.appStoreConnect.certificates.addAll(const [
        AscCertificate(id: 'b', serialNumber: '0B'),
        AscCertificate(id: 'c', serialNumber: '0C'),
      ]);
      final limit = await check(
        'POST',
        path(),
        template,
        body: {'name': 'Another'},
      );

      expect(noKey.statusCode, 400);
      expect(created.statusCode, 201);
      expect(created.json['kind'], 'apple_distribution');
      expect(
        (created.json['usedBy']! as List).single,
        containsPair('flavor', 'default'),
      );
      expect(created.body, isNot(contains('PRIVATE KEY')));
      expect(statuses, [400, 403, 404, 409]);
      expect(limit.statusCode, 409);
      final details =
          (limit.json['error']! as Map<String, Object?>)['details']!
              as Map<String, Object?>;
      expect(details['reason'], 'certificate_limit');
      expect(details['limit'], 3);
      expect(details['certificates'], hasLength(3));
    });

    test('GET /credentials and /credentials/{id} 200 and 404', () async {
      final id = await create();
      await send(
        'PUT',
        assignPath(),
        body: {'credentialId': id, 'allFlavors': true},
      );

      final list = await check(
        'GET',
        '/credentials',
        '/credentials',
        token: mcp,
      );
      final one = await check(
        'GET',
        '/credentials/$id',
        '/credentials/{credentialId}',
      );
      final none = await check(
        'GET',
        '/credentials/crd_nope',
        '/credentials/{credentialId}',
      );

      expect(
        [list.statusCode, one.statusCode, none.statusCode],
        [200, 200, 404],
      );
    });

    test('PATCH, PUT and verify of /credentials/{id}', () async {
      final id = await create();
      await create('Other');
      const template = '/credentials/{credentialId}';
      final path = '/credentials/$id';

      final statuses = [
        (await check(
          'PATCH',
          path,
          template,
          body: {'name': 'New'},
        )).statusCode,
        (await check(
          'PATCH',
          path,
          template,
          body: {'name': 'other'},
        )).statusCode,
        (await check('PATCH', path, template, body: {'name': ''})).statusCode,
        (await check(
          'PATCH',
          path,
          template,
          body: {'name': 'x'},
          token: mcp,
        )).statusCode,
        (await check(
          'PATCH',
          '/credentials/crd_nope',
          template,
          body: {'name': 'x'},
        )).statusCode,
        (await check(
          'PUT',
          path,
          template,
          body: {'token': 'sb_api_y'},
        )).statusCode,
        (await check(
          'PUT',
          path,
          template,
          body: {'kind': 'slack', 'webhookUrl': 'x'},
        )).statusCode,
        (await check(
          'POST',
          '$path/verify',
          '/credentials/{credentialId}/verify',
        )).statusCode,
        (await check(
          'POST',
          '$path/verify',
          '/credentials/{credentialId}/verify',
          token: mcp,
        )).statusCode,
      ];

      expect(statuses, [200, 409, 400, 403, 404, 200, 400, 200, 403]);
      engine.credentialVerifiers[CredentialKind.shorebird]!.answers.add(
        const VerificationResult.rejected('No.'),
      );
      expect(
        (await check(
          'PUT',
          path,
          template,
          body: {'token': 'sb_api_z'},
        )).statusCode,
        422,
      );
    });

    test('DELETE /credentials/{id} 409 with the usages, 204', () async {
      final id = await create();
      await send('PUT', assignPath(), body: {'credentialId': id});
      const template = '/credentials/{credentialId}';

      final inUse = await check('DELETE', '/credentials/$id', template);
      final forced = await check(
        'DELETE',
        '/credentials/$id?force=true',
        template,
      );
      final gone = await check('DELETE', '/credentials/$id', template);

      expect(
        [inUse.statusCode, forced.statusCode, gone.statusCode],
        [409, 204, 404],
      );
      expect(inUse.json['usedBy'], hasLength(1));
    });

    test('PUT and DELETE of a flavor credential', () async {
      final id = await create();
      const template = '/projects/{id}/flavors/{flavor}/credentials/{kind}';

      final assigned = await check(
        'PUT',
        assignPath(),
        template,
        body: {'credentialId': id, 'allFlavors': true, 'replace': true},
      );
      final forbidden = await check(
        'PUT',
        assignPath(),
        template,
        body: {'credentialId': id},
        token: mcp,
      );
      final bad = await check(
        'PUT',
        assignPath(),
        template,
        body: {'allFlavors': true},
      );
      final unknown = await check(
        'PUT',
        assignPath('nope'),
        template,
        body: {'credentialId': id},
      );
      final unassigned = await check('DELETE', assignPath(), template);
      final none = await check('DELETE', assignPath(), template);

      expect(
        [
          assigned.statusCode,
          forbidden.statusCode,
          bad.statusCode,
          unknown.statusCode,
          unassigned.statusCode,
          none.statusCode,
        ],
        [200, 403, 400, 404, 204, 404],
      );
    });

    test('GET /projects/{id}/credentials 200, 400, 404', () async {
      final id = await create();
      await send('PUT', assignPath(), body: {'credentialId': id});
      const template = '/projects/{id}/credentials';
      final base = '/projects/$projectId/credentials';

      final statuses = [
        (await check('GET', base, template, token: mcp)).statusCode,
        (await check('GET', '$base?app=x', template)).statusCode,
        (await check('GET', '$base?flavor=nope', template)).statusCode,
      ];

      expect(statuses, [200, 400, 404]);
    });

    test('the deprecated routes keep their contract', () async {
      final base = '/projects/$projectId/credentials';
      const template = '/projects/{id}/credentials';
      Map<String, Object?> legacy([String token = 'sb_api_x']) => {
        'flavor': 'default',
        'kind': 'shorebird',
        'token': token,
      };

      final created = await check('PUT', base, template, body: legacy());
      final replaced = await check(
        'PUT',
        base,
        template,
        body: legacy('sb_api_y'),
      );
      final github = await check(
        'PUT',
        base,
        template,
        body: {'flavor': 'default', 'kind': 'github', 'token': 'ghp_x'},
      );
      final forbidden = await check(
        'PUT',
        base,
        template,
        body: legacy(),
        token: mcp,
      );
      final id = created.json['id']! as String;
      final verified = await check(
        'POST',
        '$base/$id/verify',
        '/projects/{id}/credentials/{credentialId}/verify',
      );
      final removed = await check(
        'DELETE',
        '$base/$id',
        '/projects/{id}/credentials/{credentialId}',
      );
      final gone = await check(
        'DELETE',
        '$base/$id',
        '/projects/{id}/credentials/{credentialId}',
      );

      expect(
        [
          created.statusCode,
          replaced.statusCode,
          github.statusCode,
          forbidden.statusCode,
          verified.statusCode,
          removed.statusCode,
          gone.statusCode,
        ],
        [201, 200, 200, 403, 200, 204, 404],
      );
      expect(
        contract.validateSchema('SaveCredentialRequest', legacy()),
        isEmpty,
      );
    });
  });

  group('jobs', () {
    Future<RawResponse> send(String method, String path, [Object? body]) =>
        engine.request(
          path,
          method: method,
          body: body == null ? null : jsonEncode(body),
        );

    /// A job that failed at its second step, after logging a line.
    Future<Job> failedJob() async {
      engine.supervisor.handler = (process) async {
        await process.emit('hello from ${process.spec.executable}');
        return process.spec.executable == 'bad' ? 1 : 0;
      };
      final job = await engine.startJob(['good', 'bad']);
      return await engine.jobs.whenFinished(job.id);
    }

    test('request and frame schemas accept what the engine sends', () async {
      final job = await failedJob();

      expect(
        contract.validateSchema(
          'Job',
          (await engine.jobs.get(job.id)).toJson(),
        ),
        isEmpty,
      );
      expect(
        contract.validateSchema('ResumeJobRequest', {'fromStep': 1}),
        isEmpty,
      );
      expect(
        contract.validateSchema('ResumeJobRequest', {'fromStep': -1}),
        isNotEmpty,
      );
    });

    test('GET /jobs/{id}', () async {
      final job = await failedJob();

      final response = await send('GET', '/jobs/${job.id}');

      expect(response.statusCode, 200);
      expectContract(response, path: '/jobs/${job.id}');
    });

    test('GET /jobs/{id} for a job that has not run', () async {
      final job = await engine.createJob(['x']);

      final response = await send('GET', '/jobs/${job.id}');

      expectContract(response, path: '/jobs/${job.id}');
    });

    test(
      'GET /jobs/{id} for a job that needs any of two capabilities',
      () async {
        final job = await engine.jobs.create(
          workflowVersionId: 'wfv_1',
          projectId: 'prj_1',
          capabilities: const ['flutter', 'ios-sign|ios-linux'],
          steps: [
            StepPlan.of(
              const CommandStep(),
              const CommandInput(ProcessCommand('x')),
            ),
          ],
        );

        final response = await send('GET', '/jobs/${job.id}');

        expect(response.body, contains('"ios-sign|ios-linux"'));
        expectContract(response, path: '/jobs/${job.id}');
        expect(
          contract.validateSchema('CapabilityNeed', 'ios-sign|warp'),
          isNotEmpty,
        );
      },
    );

    test('GET /jobs/{id} 401 and 404', () async {
      final unauthorized = await engine.request('/jobs/job_x', token: '');
      final missing = await send('GET', '/jobs/job_nope');

      expect((unauthorized.statusCode, missing.statusCode), (401, 404));
      expectContract(unauthorized, path: '/jobs/job_x');
      expectContract(missing, path: '/jobs/job_nope');
    });

    test('POST /jobs/{id}/cancel', () async {
      final job = await engine.createJob(['x']);

      final response = await send('POST', '/jobs/${job.id}/cancel');

      expect(response.statusCode, 200);
      expectContract(response, path: '/jobs/${job.id}/cancel', method: 'POST');
    });

    test('POST /jobs/{id}/cancel 404 and 409', () async {
      final failed = await failedJob();
      final missing = await send('POST', '/jobs/job_nope/cancel');
      final ended = await send('POST', '/jobs/${failed.id}/cancel');

      expect((missing.statusCode, ended.statusCode), (404, 409));
      expectContract(missing, path: '/jobs/job_nope/cancel', method: 'POST');
      expectContract(ended, path: '/jobs/${failed.id}/cancel', method: 'POST');
    });

    test('POST /jobs/{id}/resume', () async {
      final failed = await failedJob();
      engine.supervisor.handler = (process) => 0;

      final response = await send('POST', '/jobs/${failed.id}/resume');
      await engine.jobs.whenFinished(failed.id);

      expect(response.statusCode, 202);
      expectContract(
        response,
        path: '/jobs/${failed.id}/resume',
        method: 'POST',
      );
    });

    test('POST /jobs/{id}/resume with fromStep', () async {
      final failed = await failedJob();
      engine.supervisor.handler = (process) => 0;

      final response = await send('POST', '/jobs/${failed.id}/resume', {
        'fromStep': 1,
      });
      await engine.jobs.whenFinished(failed.id);

      expect(response.statusCode, 202);
      expectContract(
        response,
        path: '/jobs/${failed.id}/resume',
        method: 'POST',
      );
    });

    test('POST /jobs/{id}/resume 400, 404 and 409', () async {
      final failed = await failedJob();
      final queued = await engine.createJob(['x']);
      final bad = await send('POST', '/jobs/${failed.id}/resume', {
        'fromStep': 'x',
      });
      final missing = await send('POST', '/jobs/job_nope/resume');
      final conflict = await send('POST', '/jobs/${queued.id}/resume');

      expect(
        (bad.statusCode, missing.statusCode, conflict.statusCode),
        (400, 404, 409),
      );
      expectContract(bad, path: '/jobs/${failed.id}/resume', method: 'POST');
      expectContract(missing, path: '/jobs/job_nope/resume', method: 'POST');
      expectContract(
        conflict,
        path: '/jobs/${queued.id}/resume',
        method: 'POST',
      );
    });

    group('GET /jobs/{id}/logs', () {
      test('401 without a token', () async {
        final response = await engine.handshake('/jobs/job_x/logs', token: '');

        expect(response.statusCode, 401);
        expectContract(response, path: '/jobs/job_x/logs');
      });

      test('400 for a bad cursor', () async {
        final job = await failedJob();

        final response = await engine.handshake(
          '/jobs/${job.id}/logs?after=-1',
        );

        expect(response.statusCode, 400);
        expectContract(response, path: '/jobs/${job.id}/logs');
      });

      test('404 for an unknown job', () async {
        final response = await engine.handshake('/jobs/job_nope/logs');

        expect(response.statusCode, 404);
        expectContract(response, path: '/jobs/job_nope/logs');
      });

      test('409 for a cursor beyond the log', () async {
        final job = await failedJob();

        final response = await engine.handshake(
          '/jobs/${job.id}/logs?after=99',
        );

        expect(response.statusCode, 409);
        expectContract(response, path: '/jobs/${job.id}/logs');
      });

      test('426 for a plain request', () async {
        final job = await failedJob();

        final response = await engine.request('/jobs/${job.id}/logs');

        expect(response.statusCode, 426);
        expectContract(response, path: '/jobs/${job.id}/logs');
      });

      test('101 and frames that match LogFrame', () async {
        final job = await failedJob();

        final logs = await engine.connectLogs(job.id);
        addTearDown(logs.close);

        contract.expectResponse(
          method: 'GET',
          path: '/jobs/${job.id}/logs',
          statusCode: 101,
          body: '',
        );
        final frames = await logs.all();
        expect(frames, hasLength(3));
        for (final frame in frames) {
          expect(contract.validateSchema('LogFrame', frame.toJson()), isEmpty);
        }
      });
    });
  });
}

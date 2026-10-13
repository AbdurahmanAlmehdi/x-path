@Tags(['contract'])
library;

import 'dart:convert';

import 'package:test/test.dart';
import 'package:xp_api/testing.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

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

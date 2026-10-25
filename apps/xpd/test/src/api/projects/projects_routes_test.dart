import 'dart:convert';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../helpers/test_engine.dart';

/// A repository that holds a project nobody may remove.
class _InUseRepository extends InMemoryProjectRepository {
  @override
  Future<bool> remove(String id) async => throw ProjectInUseException(id);
}

void main() {
  late TestEngine engine;

  setUp(() async {
    engine = await TestEngine.start();
    engine.folders['/work/app'] = projectFiles;
  });
  tearDown(() => engine.close());

  Future<RawResponse> send(
    String method,
    String path, {
    Object? json,
    String? body,
    String? token,
  }) => engine.request(
    path,
    method: method,
    token: token,
    body: body ?? (json == null ? null : jsonEncode(json)),
  );

  Future<Project> add([Map<String, Object?>? request]) async {
    final response = await send(
      'POST',
      '/projects',
      json: request ?? {'path': '/work/app'},
    );
    expect(response.statusCode, 201, reason: response.body);
    return Project.fromJson(response.json);
  }

  String errorCode(RawResponse response) =>
      (response.json['error']! as Map<String, dynamic>)['code']! as String;

  String errorMessage(RawResponse response) =>
      (response.json['error']! as Map<String, dynamic>)['message']! as String;

  group('POST /projects', () {
    test('adds by path, scans, and points at the project', () async {
      final response = await send(
        'POST',
        '/projects',
        json: {'path': '/work/app'},
      );

      final project = Project.fromJson(response.json);
      expect(response.statusCode, 201);
      expect(project.fullName, 'octo/app');
      expect(project.githubRepoId, 42);
      expect(project.localPath, '/work/app');
      expect(project.profile.apps.single.name, 'demo');
      expect(project.defaultBaseBranch, 'main');
      expect(project.findings, isNotEmpty);
      expect(project.scannedAt, engine.clock.now());
    });

    test('adds by remote, from the mirror', () async {
      final project = await add({'remote': 'https://github.com/octo/app.git'});

      expect(project.localPath, isNull);
      expect(project.profile.apps.single.name, 'demo');
    });

    test('tells the Location of the project', () async {
      final client = await engine.request(
        '/projects',
        method: 'POST',
        body: jsonEncode({'remote': 'octo/app'}),
      );

      expect(client.statusCode, 201);
      expect(
        (await send('GET', '/projects/${client.json['id']}')).statusCode,
        200,
      );
    });

    test('announces the project and its scan on the event stream', () async {
      final stream = await engine.connect(after: 0);
      addTearDown(stream.close);
      await stream.take(2); // stream.opened and engine.started

      final project = await add();

      final events = await stream.take(2);
      expect(events.map((e) => e.event), [
        ProjectAdded(projectId: project.id, fullName: 'octo/app'),
        ProjectScanned(
          projectId: project.id,
          errors: 0,
          warnings: project.findings
              .where((f) => f.severity == FindingSeverity.warning)
              .length,
        ),
      ]);
    });

    test(
      'rejects a body that is not JSON, not an object or the wrong type',
      () async {
        for (final body in [
          '{nope',
          '[1]',
          '"x"',
          '{"path": 3}',
          '{"remote": []}',
        ]) {
          final response = await send('POST', '/projects', body: body);

          expect(response.statusCode, 400, reason: body);
          expect(errorCode(response), 'invalid_request', reason: body);
        }
      },
    );

    test('names the field of the wrong type', () async {
      final response = await send('POST', '/projects', body: '{"path": 3}');

      expect(errorMessage(response), contains('path'));
    });

    test('rejects a request with both or neither of path and remote', () async {
      for (final json in [
        <String, Object?>{},
        {'path': '/work/app', 'remote': 'octo/app'},
      ]) {
        final response = await send('POST', '/projects', json: json);

        expect(response.statusCode, 400);
        expect(errorMessage(response), contains('exactly one'));
      }
    });

    test(
      'rejects a folder that is not there and a remote it cannot reach',
      () async {
        final missing = await send(
          'POST',
          '/projects',
          json: {'path': '/nope'},
        );
        final other = await send(
          'POST',
          '/projects',
          json: {'remote': 'svn://example.com/x/y'},
        );

        expect(missing.statusCode, 400);
        expect(other.statusCode, 400);
      },
    );

    test('adds a repository on another host by its SSH URL', () async {
      engine.github.failure = Exception('GitHub must not be asked');

      final project = await add({'remote': 'git@bitbucket.org:ws/app.git'});

      expect(project.host, 'bitbucket.org');
      expect(project.sourceKey, matches(RegExp(r'^h[0-9a-f]{16}$')));
      expect(project.githubRepoId, isNull);
      expect(project.fullName, 'ws/app');
    });

    test('offers the SSH URL of an HTTPS remote on another host', () async {
      final response = await send(
        'POST',
        '/projects',
        json: {'remote': 'https://bitbucket.org/ws/app.git'},
      );

      expect(response.statusCode, 422);
      expect(errorCode(response), 'ssh_url_required');
      expect(
        errorMessage(response),
        'XPath has no credentials for bitbucket.org over HTTPS; use the SSH '
        'URL git@bitbucket.org:ws/app.git.',
      );
      expect(response.json['sshUrl'], 'git@bitbucket.org:ws/app.git');
    });

    test('answers 409 for a repository that is a project already', () async {
      final first = await add();

      final again = await send(
        'POST',
        '/projects',
        json: {'remote': 'octo/app'},
      );

      expect(again.statusCode, 409);
      expect(errorCode(again), 'conflict');
      expect(errorMessage(again), contains(first.id));
    });

    test('answers 404 for a repository GitHub cannot find', () async {
      final response = await send(
        'POST',
        '/projects',
        json: {'remote': 'octo/gone'},
      );

      expect(response.statusCode, 404);
      expect(errorCode(response), 'not_found');
    });

    test('answers 502 when GitHub or git fails, without internals', () async {
      engine.github.failure = const GitHubForbiddenException(
        'API rate limit exceeded',
        rateLimited: true,
      );
      final github = await send(
        'POST',
        '/projects',
        json: {'remote': 'octo/app'},
      );
      engine.github.failure = null;
      engine.git.fetchFailure = const GitException('network down');
      final git = await send('POST', '/projects', json: {'remote': 'octo/app'});

      expect(github.statusCode, 502);
      expect(errorCode(github), 'upstream_error');
      expect(errorMessage(github), contains('API rate limit exceeded'));
      expect(git.statusCode, 502);
      expect(errorMessage(git), 'network down');
    });

    test('answers 503 while the secrets are locked', () async {
      engine.github.failure = const SecretsLockedException('Keychain locked');

      final response = await send(
        'POST',
        '/projects',
        json: {'remote': 'octo/app'},
      );

      expect(response.statusCode, 503);
      expect(errorCode(response), 'secrets_locked');
      expect(errorMessage(response), isNot(contains('Keychain')));
    });

    test('answers 500 for a failure nobody expected', () async {
      engine.github.failure = const FormatException('boom');

      final response = await send(
        'POST',
        '/projects',
        json: {'remote': 'octo/app'},
      );

      expect(response.statusCode, 500);
      expect(errorCode(response), 'internal');
      expect(engine.errors, hasLength(1));
    });
  });

  group('GET /projects', () {
    test('lists the projects', () async {
      expect((await send('GET', '/projects')).json['projects'], isEmpty);
      final project = await add();

      final listed = ProjectsResponse.fromJson(
        (await send('GET', '/projects')).json,
      );

      expect(listed.projects, [project]);
    });

    test('shows one project', () async {
      final project = await add();

      final response = await send('GET', '/projects/${project.id}');

      expect(Project.fromJson(response.json), project);
    });

    test('answers 404 for a project that is not there', () async {
      final response = await send('GET', '/projects/prj_nope');

      expect(response.statusCode, 404);
      expect(errorMessage(response), contains('prj_nope'));
    });
  });

  group('POST /projects/{id}/scan', () {
    test('scans again and reports what changed', () async {
      final project = await add();
      engine.folders['/work/app'] = {...projectFiles, '.fvmrc': 'broken'};
      engine.clock.advance(const Duration(minutes: 5));

      final response = await send('POST', '/projects/${project.id}/scan');

      final scanned = Project.fromJson(response.json);
      expect(response.statusCode, 200);
      expect(scanned.findings.map((f) => f.code), contains('fvmrc_invalid'));
      expect(scanned.scannedAt, engine.clock.now());
      expect(await send('GET', '/projects/${project.id}'), isNotNull);
    });

    test('answers 404 for a project that is not there', () async {
      expect((await send('POST', '/projects/prj_nope/scan')).statusCode, 404);
    });
  });

  group('PATCH /projects/{id}', () {
    test('edits survive a rescan', () async {
      final project = await add();

      await send(
        'PATCH',
        '/projects/${project.id}',
        json: {
          'defaultBaseBranch': 'dev',
          'apps': [
            {'path': '.', 'storeCountry': 'ly'},
          ],
        },
      );
      final rescanned = Project.fromJson(
        (await send('POST', '/projects/${project.id}/scan')).json,
      );

      expect(rescanned.defaultBaseBranch, 'dev');
      expect(rescanned.profile.apps.single.storeCountry, 'ly');
    });

    test('rejects what the profile does not have, and bad bodies', () async {
      final project = await add();

      final unknown = await send(
        'PATCH',
        '/projects/${project.id}',
        json: {
          'apps': [
            {'path': 'apps/nope'},
          ],
        },
      );
      final badType = await send(
        'PATCH',
        '/projects/${project.id}',
        body: '{"apps": [{"path": 1}]}',
      );
      final notJson = await send(
        'PATCH',
        '/projects/${project.id}',
        body: 'nope',
      );

      expect(unknown.statusCode, 400);
      expect(errorMessage(unknown), contains('apps/nope'));
      expect(badType.statusCode, 400);
      expect(notJson.statusCode, 400);
    });

    test('answers 404 for a project that is not there', () async {
      final response = await send('PATCH', '/projects/prj_nope', json: {});

      expect(response.statusCode, 404);
    });
  });

  group('DELETE /projects/{id}', () {
    test('removes the project and announces it', () async {
      final project = await add();

      final response = await send('DELETE', '/projects/${project.id}');

      expect(response.statusCode, 204);
      expect(response.body, isEmpty);
      expect((await send('GET', '/projects')).json['projects'], isEmpty);
      expect(
        engine.events.subscribe(after: 0).map((e) => e.event),
        emitsThrough(ProjectRemoved(projectId: project.id)),
      );
    });

    test('answers 404 for a project that is not there', () async {
      expect((await send('DELETE', '/projects/prj_nope')).statusCode, 404);
    });

    test('answers 409 for a project with releases or jobs', () async {
      final busy = await TestEngine.start(
        projectRepository: _InUseRepository(),
      );
      addTearDown(busy.close);

      final response = await busy.request('/projects/prj_x', method: 'DELETE');

      expect(response.statusCode, 409);
      expect(errorCode(response), 'conflict');
    });
  });

  test('every route needs a device token', () async {
    for (final (method, path) in [
      ('POST', '/projects'),
      ('GET', '/projects'),
      ('GET', '/projects/prj_x'),
      ('POST', '/projects/prj_x/scan'),
      ('PATCH', '/projects/prj_x'),
      ('DELETE', '/projects/prj_x'),
    ]) {
      final response = await send(
        method,
        path,
        token: 'xpt_nope',
        body: method == 'POST' || method == 'PATCH' ? '{}' : null,
      );

      expect(response.statusCode, 401, reason: '$method $path');
    }
  });
}

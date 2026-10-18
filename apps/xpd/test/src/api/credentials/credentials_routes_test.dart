import 'dart:convert';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../helpers/test_engine.dart';

void main() {
  late TestEngine engine;
  late String projectId;
  late String mcp;

  setUp(() async {
    engine = await TestEngine.start();
    engine.folders['/work/app'] = projectFiles;
    final added = await engine.request(
      '/projects',
      method: 'POST',
      body: jsonEncode({'path': '/work/app'}),
    );
    projectId = Project.fromJson(added.json).id;
    for (final (id, name) in [('flv_1', 'default'), ('flv_2', 'beta')]) {
      engine.credentialRepository.flavors.add(
        CredentialFlavor(
          id: id,
          projectId: projectId,
          appPath: '.',
          name: name,
          iosBundleId: 'com.example',
          androidAppId: 'com.example',
        ),
      );
    }
    engine.credentialRepository.flavors.add(
      CredentialFlavor(
        id: 'flv_3',
        projectId: projectId,
        appPath: 'apps/admin',
        name: 'default',
      ),
    );
    mcp = (await engine.tokens.issue(
      name: 'agent',
      kind: DeviceTokenKind.mcp,
    )).secret;
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

  Map<String, Object?> shorebird({
    String name = 'Studio Shorebird',
    String token = 'sb_api_secret',
  }) => {'name': name, 'kind': 'shorebird', 'token': token};

  Future<NamedCredential> create([Map<String, Object?>? json]) async {
    final response = await send(
      'POST',
      '/credentials',
      json: json ?? shorebird(),
    );
    expect(response.statusCode, 201, reason: response.body);
    return NamedCredential.fromJson(response.json);
  }

  Future<RawResponse> assign(
    String credentialId, {
    String flavor = 'default',
    String kind = 'shorebird',
    String query = '',
    bool allFlavors = false,
    bool replace = false,
    String? token,
  }) => send(
    'PUT',
    '/projects/$projectId/flavors/$flavor/credentials/$kind$query',
    json: {
      'credentialId': credentialId,
      'allFlavors': allFlavors,
      'replace': replace,
    },
    token: token,
  );

  String errorCode(RawResponse response) =>
      (response.json['error']! as Map<String, dynamic>)['code']! as String;

  String errorMessage(RawResponse response) =>
      (response.json['error']! as Map<String, dynamic>)['message']! as String;

  group('POST /credentials', () {
    test('verifies, stores and answers 201 with where it is', () async {
      engine.credentialVerifiers[CredentialKind.shorebird]!.answers.add(
        const VerificationResult.verified(account: 'dev@example.com'),
      );

      final response = await send('POST', '/credentials', json: shorebird());

      expect(response.statusCode, 201);
      final credential = NamedCredential.fromJson(response.json);
      expect(response.headers['location'], '/credentials/${credential.id}');
      expect(credential.name, 'Studio Shorebird');
      expect(credential.account, 'dev@example.com');
      expect(credential.usedBy, isEmpty);
      expect(response.body, isNot(contains('sb_api_secret')));
      expect(
        engine.credentialSecrets.text('credential.${credential.id}'),
        'sb_api_secret',
      );
      expect(engine.masker.secrets, contains('sb_api_secret'));
    });

    test('answers 409 for a name that is taken', () async {
      await create();

      final response = await send(
        'POST',
        '/credentials',
        json: shorebird(name: 'STUDIO SHOREBIRD'),
      );

      expect(response.statusCode, 409);
      expect(errorCode(response), 'conflict');
    });

    test('answers 422 and 502 when the check says no or cannot', () async {
      engine.credentialVerifiers[CredentialKind.shorebird]!.answers.addAll([
        const VerificationResult.rejected('Not a key.', fix: 'Make one.'),
        const VerificationResult.unreachable('Offline.'),
      ]);

      final refused = await send('POST', '/credentials', json: shorebird());
      final unreachable = await send('POST', '/credentials', json: shorebird());

      expect(refused.statusCode, 422);
      expect(errorMessage(refused), 'Not a key. Make one.');
      expect(unreachable.statusCode, 502);
      expect(errorMessage(unreachable), 'Offline. Nothing was stored.');
      expect(await engine.credentialRepository.list(), isEmpty);
    });

    test('answers 400 for a malformed request, and for github', () async {
      for (final json in <Map<String, Object?>>[
        {'kind': 'shorebird', 'token': 'x'},
        {'name': 'n', 'kind': 'dropbox'},
        {'name': 'n', 'kind': 'shorebird'},
        {'name': 'n', 'kind': 'github', 'token': 'x'},
        {'name': 'n', 'kind': 'shorebird', 'token': 7, 'x': 'SECRET-EXTRA'},
      ]) {
        final response = await send('POST', '/credentials', json: json);

        expect(response.statusCode, 400, reason: '$json');
        expect(response.body, isNot(contains('SECRET-EXTRA')));
      }
    });

    test('answers 403 to an mcp token and 503 when locked', () async {
      final forbidden = await send(
        'POST',
        '/credentials',
        json: shorebird(),
        token: mcp,
      );
      engine.credentialSecrets.failure = const SecretsLockedException('l');
      final locked = await send('POST', '/credentials', json: shorebird());

      expect(forbidden.statusCode, 403);
      expect(errorCode(forbidden), 'forbidden');
      expect(locked.statusCode, 503);
    });
  });

  group('GET /credentials', () {
    test('lists the credentials with their usages, to an mcp token', () async {
      final created = await create();
      await assign(created.id, allFlavors: true);

      final response = await send('GET', '/credentials', token: mcp);

      expect(response.statusCode, 200);
      final listed = NamedCredentialsResponse.fromJson(response.json)
          .credentials
          .single;
      expect(listed.usedBy.map((usage) => usage.flavor), ['beta', 'default']);
      expect(response.body, isNot(contains('sb_api_secret')));
    });

    test('gets one, or answers 404', () async {
      final created = await create();

      final got = await send('GET', '/credentials/${created.id}', token: mcp);

      expect(NamedCredential.fromJson(got.json).id, created.id);
      expect((await send('GET', '/credentials/crd_nope')).statusCode, 404);
    });
  });

  group('PATCH /credentials/{id}', () {
    test('renames, keeping the id', () async {
      final created = await create();

      final response = await send(
        'PATCH',
        '/credentials/${created.id}',
        json: {'name': 'Renamed'},
      );

      expect(response.statusCode, 200);
      expect(NamedCredential.fromJson(response.json).name, 'Renamed');
      expect(NamedCredential.fromJson(response.json).id, created.id);
    });

    test('answers 409, 400, 403 and 404', () async {
      final created = await create();
      await create(shorebird(name: 'Other'));
      final path = '/credentials/${created.id}';

      expect(
        (await send('PATCH', path, json: {'name': 'other'})).statusCode,
        409,
      );
      expect((await send('PATCH', path, json: {'name': ''})).statusCode, 400);
      expect(
        (await send('PATCH', path, json: {'name': 'x'}, token: mcp)).statusCode,
        403,
      );
      expect(
        (await send(
          'PATCH',
          '/credentials/crd_nope',
          json: {'name': 'x'},
        )).statusCode,
        404,
      );
    });
  });

  group('PUT /credentials/{id}', () {
    test('stores a new secret under the same name', () async {
      final created = await create();

      final response = await send(
        'PUT',
        '/credentials/${created.id}',
        json: {'kind': 'shorebird', 'token': 'sb_api_new'},
      );

      expect(response.statusCode, 200);
      expect(NamedCredential.fromJson(response.json).name, 'Studio Shorebird');
      expect(
        engine.credentialSecrets.text('credential.${created.id}'),
        'sb_api_new',
      );
      expect(response.body, isNot(contains('sb_api_new')));
    });

    test('answers 400 for another kind, 422 when refused', () async {
      final created = await create();
      final path = '/credentials/${created.id}';
      engine.credentialVerifiers[CredentialKind.shorebird]!.answers.add(
        const VerificationResult.rejected('No.'),
      );

      final kind = await send(
        'PUT',
        path,
        json: {'kind': 'slack', 'webhookUrl': 'x'},
      );
      final refused = await send('PUT', path, json: {'token': 'sb_api_bad'});

      expect(kind.statusCode, 400);
      expect(refused.statusCode, 422);
      expect(
        engine.credentialSecrets.text('credential.${created.id}'),
        'sb_api_secret',
      );
    });
  });

  group('POST /credentials/{id}/verify', () {
    test('checks the credential and its flavors', () async {
      final created = await create();
      await assign(created.id);
      engine.clock.advance(const Duration(days: 1));

      final response = await send('POST', '/credentials/${created.id}/verify');

      expect(response.statusCode, 200);
      final checked = NamedCredential.fromJson(response.json);
      expect(checked.checkedAt, engine.clock.now());
      expect(checked.usedBy.single.checkedAt, engine.clock.now());
    });

    test('answers 403 to an mcp token', () async {
      final created = await create();

      expect(
        (await send(
          'POST',
          '/credentials/${created.id}/verify',
          token: mcp,
        )).statusCode,
        403,
      );
    });
  });

  group('DELETE /credentials/{id}', () {
    test('deletes an unused credential and its secret', () async {
      final created = await create();

      final response = await send('DELETE', '/credentials/${created.id}');

      expect(response.statusCode, 204);
      expect(engine.credentialSecrets.values, isEmpty);
    });

    test('answers 409 with the usages unless forced', () async {
      final created = await create();
      await assign(created.id, allFlavors: true);

      final refused = await send('DELETE', '/credentials/${created.id}');

      expect(refused.statusCode, 409);
      expect(errorCode(refused), 'credential_in_use');
      expect(
        [
          for (final usage in refused.json['usedBy']! as List<dynamic>)
            CredentialUsage.fromJson(usage as Map<String, dynamic>).flavor,
        ],
        ['beta', 'default'],
      );
      expect(
        (await send(
          'DELETE',
          '/credentials/${created.id}?force=false',
        )).statusCode,
        409,
      );

      final forced = await send(
        'DELETE',
        '/credentials/${created.id}?force=true',
      );

      expect(forced.statusCode, 204);
      expect(await engine.credentialRepository.assignments(), isEmpty);
    });

    test('answers 400 for a bad force, 403 and 404', () async {
      final created = await create();

      expect(
        (await send(
          'DELETE',
          '/credentials/${created.id}?force=yes',
        )).statusCode,
        400,
      );
      expect(
        (await send(
          'DELETE',
          '/credentials/${created.id}',
          token: mcp,
        )).statusCode,
        403,
      );
      expect((await send('DELETE', '/credentials/crd_nope')).statusCode, 404);
    });
  });

  group('PUT /projects/{id}/flavors/{flavor}/credentials/{kind}', () {
    test('this flavor uses it, checked', () async {
      final created = await create();

      final response = await assign(created.id);

      expect(response.statusCode, 200);
      final result = AssignCredentialResponse.fromJson(response.json);
      expect(result.assigned.single.flavor, 'default');
      expect(result.assigned.single.name, 'Studio Shorebird');
      expect(
        result.assigned.single.assignmentStatus,
        CredentialStatus.verified,
      );
      expect(result.kept, isEmpty);
    });

    test('every flavor of the app, keeping or replacing others', () async {
      final mine = await create();
      final other = await create(shorebird(name: 'Other'));
      await assign(other.id, flavor: 'beta');

      final kept = AssignCredentialResponse.fromJson(
        (await assign(mine.id, allFlavors: true)).json,
      );
      final replaced = AssignCredentialResponse.fromJson(
        (await assign(mine.id, allFlavors: true, replace: true)).json,
      );

      expect(kept.kept.single.flavor, 'beta');
      expect(kept.assigned.single.flavor, 'default');
      expect(replaced.assigned.map((c) => c.flavor), ['beta', 'default']);
    });

    test('an app below the root by the app query', () async {
      final created = await create();

      final response = await assign(created.id, query: '?app=apps/admin');

      expect(
        AssignCredentialResponse.fromJson(response.json).assigned.single.app,
        'apps/admin',
      );
    });

    test('answers 400, 403 and 404', () async {
      final created = await create();

      expect((await assign(created.id, kind: 'dropbox')).statusCode, 400);
      expect((await assign(created.id, kind: 'slack')).statusCode, 400);
      expect((await assign(created.id, kind: 'github')).statusCode, 400);
      expect((await assign(created.id, query: '?app=')).statusCode, 400);
      expect(
        (await send(
          'PUT',
          '/projects/$projectId/flavors/default/credentials/shorebird',
          json: {'allFlavors': true},
        )).statusCode,
        400,
      );
      expect((await assign(created.id, token: mcp)).statusCode, 403);
      expect((await assign(created.id, flavor: 'nope')).statusCode, 404);
      expect((await assign('crd_nope')).statusCode, 404);
    });
  });

  group('DELETE /projects/{id}/flavors/{flavor}/credentials/{kind}', () {
    test('the flavor stops using it; it stays', () async {
      final created = await create();
      await assign(created.id);

      final response = await send(
        'DELETE',
        '/projects/$projectId/flavors/default/credentials/shorebird',
      );

      expect(response.statusCode, 204);
      expect(await engine.credentialRepository.assignments(), isEmpty);
      expect(await engine.credentialRepository.get(created.id), isNotNull);
    });

    test('answers 404 without one and 403 to an mcp token', () async {
      const path = '/flavors/default/credentials/shorebird';

      expect(
        (await send('DELETE', '/projects/$projectId$path')).statusCode,
        404,
      );
      expect(
        (await send(
          'DELETE',
          '/projects/$projectId$path',
          token: mcp,
        )).statusCode,
        403,
      );
    });
  });

  group('GET /projects/{id}/credentials', () {
    test('lists what each flavor uses, without a secret', () async {
      final created = await create();
      await assign(created.id, allFlavors: true);

      final response = await send(
        'GET',
        '/projects/$projectId/credentials',
        token: mcp,
      );

      expect(response.statusCode, 200);
      final list = CredentialsResponse.fromJson(response.json).credentials;
      expect([for (final c in list) c.flavor], ['beta', 'default']);
      expect(list.first.name, 'Studio Shorebird');
      expect(response.body, isNot(contains('sb_api_secret')));
    });

    test('narrows to a flavor and answers 400 and 404', () async {
      final created = await create();
      await assign(created.id, allFlavors: true);
      final base = '/projects/$projectId/credentials';

      final one = await send('GET', '$base?flavor=default');

      expect(CredentialsResponse.fromJson(one.json).credentials, hasLength(1));
      expect((await send('GET', '$base?app=apps/x')).statusCode, 400);
      expect((await send('GET', '$base?flavor=nope')).statusCode, 404);
      expect(
        (await send('GET', '/projects/prj_nope/credentials')).statusCode,
        404,
      );
      expect((await send('GET', base, token: '')).statusCode, 401);
    });
  });

  group('the deprecated PUT /projects/{id}/credentials', () {
    Future<RawResponse> save(Map<String, Object?> json, {String? token}) =>
        send(
          'PUT',
          '/projects/$projectId/credentials',
          json: {'flavor': 'default', ...json},
          token: token,
        );

    test('creates a named credential for the flavor (201), then gives it '
        'a new secret (200)', () async {
      final first = await save({'kind': 'shorebird', 'token': 'sb_api_one'});
      final second = await save({'kind': 'shorebird', 'token': 'sb_api_two'});

      expect(first.statusCode, 201);
      final credential = Credential.fromJson(first.json);
      expect(first.headers['location'], '/credentials/${credential.id}');
      expect(credential.name, startsWith('Shorebird API key · '));
      expect(credential.flavor, 'default');
      expect(second.statusCode, 200);
      expect(Credential.fromJson(second.json).id, credential.id);
      expect(
        engine.credentialSecrets.text('credential.${credential.id}'),
        'sb_api_two',
      );
    });

    test('makes a GitHub token the engine token', () async {
      final response = await save({'kind': 'github', 'token': 'ghp_secret'});

      expect(response.statusCode, 200);
      expect(engine.credentialSecrets.text('github.token'), 'ghp_secret');
      expect(response.body, isNot(contains('ghp_secret')));
    });

    test('answers 400, 403, 404 and 409', () async {
      await create(shorebird(name: 'Taken'));

      expect((await save({'kind': 'dropbox'})).statusCode, 400);
      expect(
        (await save({
          'kind': 'shorebird',
          'token': 'sb_api_x',
        }, token: mcp)).statusCode,
        403,
      );
      expect(
        (await send(
          'PUT',
          '/projects/$projectId/credentials',
          json: {'flavor': 'nope', 'kind': 'shorebird', 'token': 'x'},
        )).statusCode,
        404,
      );
      expect(
        (await save({
          'kind': 'shorebird',
          'name': 'taken',
          'token': 'sb_api_x',
        })).statusCode,
        409,
      );
    });

    test('keeps the secret out of a failure inside', () async {
      engine.credentialSecrets.failure = const SecretStoreException('disk');

      final response = await save({
        'kind': 'shorebird',
        'token': 'sb_api_must_not_leak',
      });

      expect(response.statusCode, 500);
      expect(response.body, isNot(contains('sb_api_must_not_leak')));
      expect('${engine.errors}', isNot(contains('sb_api_must_not_leak')));
    });
  });

  group('the deprecated verify and delete of a project', () {
    late NamedCredential created;

    setUp(() async {
      created = await create();
      await assign(created.id);
    });

    test('verifies as the flavor sees it', () async {
      final response = await send(
        'POST',
        '/projects/$projectId/credentials/${created.id}/verify',
      );

      expect(response.statusCode, 200);
      expect(Credential.fromJson(response.json).flavor, 'default');
    });

    test('removes it from the project and deletes it', () async {
      final response = await send(
        'DELETE',
        '/projects/$projectId/credentials/${created.id}',
      );

      expect(response.statusCode, 204);
      expect(await engine.credentialRepository.get(created.id), isNull);
    });

    test('answers 404 for a credential the project does not use', () async {
      final other = await create(shorebird(name: 'Other'));

      expect(
        (await send(
          'POST',
          '/projects/$projectId/credentials/${other.id}/verify',
        )).statusCode,
        404,
      );
      expect(
        (await send(
          'DELETE',
          '/projects/$projectId/credentials/${other.id}',
        )).statusCode,
        404,
      );
    });
  });
}

import 'dart:convert';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../helpers/test_engine.dart';

const _flavor = CredentialFlavor(
  id: 'flv_1',
  projectId: 'set below',
  appPath: '.',
  name: 'default',
  iosBundleId: 'com.example',
  androidAppId: 'com.example',
);

void main() {
  late TestEngine engine;
  late String projectId;

  setUp(() async {
    engine = await TestEngine.start();
    engine.folders['/work/app'] = projectFiles;
    final added = await engine.request(
      '/projects',
      method: 'POST',
      body: jsonEncode({'path': '/work/app'}),
    );
    projectId = Project.fromJson(added.json).id;
    engine.credentialRepository.flavors.add(
      CredentialFlavor(
        id: _flavor.id,
        projectId: projectId,
        appPath: _flavor.appPath,
        name: _flavor.name,
        iosBundleId: _flavor.iosBundleId,
        androidAppId: _flavor.androidAppId,
      ),
    );
  });
  tearDown(() => engine.close());

  Future<RawResponse> send(
    String method,
    String path, {
    Object? json,
    String? body,
    String? token,
  }) => engine.request(
    '/projects/$projectId/credentials$path',
    method: method,
    token: token,
    body: body ?? (json == null ? null : jsonEncode(json)),
  );

  Future<RawResponse> save(Map<String, Object?> material) =>
      send('PUT', '', json: {'flavor': 'default', ...material});

  Map<String, Object?> github([String token = 'ghp_secret']) => {
    'kind': 'github',
    'token': token,
  };

  String errorCode(RawResponse response) =>
      (response.json['error']! as Map<String, dynamic>)['code']! as String;

  String errorMessage(RawResponse response) =>
      (response.json['error']! as Map<String, dynamic>)['message']! as String;

  group('PUT /projects/{id}/credentials', () {
    test('verifies, stores and answers 201 with where it is', () async {
      engine.credentialVerifiers[CredentialKind.github]!.answers.add(
        const VerificationResult.verified(account: 'octocat'),
      );

      final response = await save(github());

      expect(response.statusCode, 201);
      final credential = Credential.fromJson(response.json);
      expect(credential.kind, CredentialKind.github);
      expect(credential.status, CredentialStatus.verified);
      expect(credential.account, 'octocat');
      expect(credential.flavor, 'default');
      expect(credential.app, '.');
      expect(credential.projectId, projectId);
      expect(
        response.json.toString(),
        isNot(contains('ghp_secret')),
        reason: 'the response never repeats the secret',
      );
      expect(engine.credentialSecrets.text('github.token'), 'ghp_secret');
      expect(engine.masker.secrets, contains('ghp_secret'));
    });

    test('answers 200 when it replaces the credential', () async {
      await save(github());

      final response = await save(github('ghp_new'));

      expect(response.statusCode, 200);
      expect(engine.credentialSecrets.text('github.token'), 'ghp_new');
      expect(await engine.credentialRepository.list(), hasLength(1));
    });

    test('announces the save on /events', () async {
      final stream = await engine.connect(after: 0);
      addTearDown(stream.close);
      await stream.take(2); // stream.opened and engine.started
      await stream.take(2); // project.added and project.scanned

      final response = await save(github());

      final credential = Credential.fromJson(response.json);
      expect(
        (await stream.take(1)).single.event,
        CredentialSaved(
          credentialId: credential.id,
          projectId: projectId,
          kind: CredentialKind.github,
          replaced: false,
        ),
      );
    });

    test(
      'answers 422 with the reason and the fix, and stores nothing',
      () async {
        engine.credentialVerifiers[CredentialKind.ascKey]!.answers.add(
          const VerificationResult.rejected(
            'App Store Connect refused the API key ABC.',
            fix: 'Create a new key.',
          ),
        );

        final response = await save({
          'kind': 'asc_key',
          'keyId': 'ABC',
          'issuerId': 'ISS',
          'privateKey': 'PRIVATE-KEY-TEXT',
        });

        expect(response.statusCode, 422);
        expect(errorCode(response), 'credential_rejected');
        expect(
          errorMessage(response),
          'App Store Connect refused the API key ABC. Create a new key.',
        );
        expect(response.body, isNot(contains('PRIVATE-KEY-TEXT')));
        expect(engine.credentialSecrets.values, isEmpty);
        expect(await engine.credentialRepository.list(), isEmpty);
      },
    );

    test('answers 422 for a key file that is not one', () async {
      final response = await save({
        'kind': 'play_sa',
        'serviceAccount': '{"type": "user", "note": "SECRET-NOTE"}',
      });

      expect(response.statusCode, 422);
      expect(response.body, isNot(contains('SECRET-NOTE')));
    });

    test('answers 502 when the check could not be made', () async {
      engine.credentialVerifiers[CredentialKind.github]!.answers.add(
        const VerificationResult.unreachable('GitHub is down.', fix: 'Retry.'),
      );

      final response = await save(github());

      expect(response.statusCode, 502);
      expect(errorCode(response), 'upstream_error');
      expect(
        errorMessage(response),
        'GitHub is down. Retry. Nothing was stored.',
      );
      expect(engine.credentialSecrets.values, isEmpty);
    });

    test('answers 400 for a malformed request', () async {
      for (final json in <Map<String, Object?>>[
        {'flavor': 'default'},
        {'flavor': 'default', 'kind': 'dropbox'},
        {'kind': 'github', 'token': 'x'},
        {'flavor': 'default', 'kind': 'github'},
        {'flavor': 'default', 'kind': 'github', 'token': 7},
      ]) {
        final response = await send('PUT', '', json: json);

        expect(response.statusCode, 400, reason: '$json');
        expect(errorCode(response), 'invalid_request');
      }
      expect((await send('PUT', '', body: 'not json')).statusCode, 400);
      expect((await send('PUT', '', body: '[]')).statusCode, 400);
    });

    test('never repeats a secret of a malformed request', () async {
      final response = await send(
        'PUT',
        '',
        json: {
          'flavor': 'default',
          'kind': 'github',
          'token': 12345,
          'extra': 'SECRET-EXTRA',
        },
      );

      expect(response.statusCode, 400);
      expect(response.body, isNot(contains('SECRET-EXTRA')));
    });

    test('answers 404 for an unknown project or flavor', () async {
      final noFlavor = await send(
        'PUT',
        '',
        json: {'flavor': 'nope', 'kind': 'github', 'token': 'x'},
      );
      final noProject = await engine.request(
        '/projects/prj_nope/credentials',
        method: 'PUT',
        body: jsonEncode({'flavor': 'default', ...github()}),
      );

      expect(noFlavor.statusCode, 404);
      expect(noProject.statusCode, 404);
      expect(errorCode(noProject), 'not_found');
    });

    test('answers 503 when the secrets are locked', () async {
      engine.credentialSecrets.failure = const SecretsLockedException('locked');

      final response = await save(github());

      expect(response.statusCode, 503);
      expect(errorCode(response), 'secrets_locked');
    });

    test('keeps the secret out of the errors of a failure inside', () async {
      engine.credentialSecrets.failure = const SecretStoreException('disk');

      final response = await save(github('ghp_must_not_leak'));

      expect(response.statusCode, 500);
      expect(response.body, isNot(contains('ghp_must_not_leak')));
      expect('${engine.errors}', isNot(contains('ghp_must_not_leak')));
    });

    test('answers 401 without a token', () async {
      expect(
        (await send('PUT', '', json: github(), token: '')).statusCode,
        401,
      );
    });
  });

  group('GET /projects/{id}/credentials', () {
    test('lists the credentials without a secret', () async {
      await save(github());
      await save({
        'kind': 'slack',
        'webhookUrl': 'https://hooks.slack.com/services/T/B/SECRETPART',
      });

      final response = await send('GET', '');

      expect(response.statusCode, 200);
      final list = CredentialsResponse.fromJson(response.json).credentials;
      expect(
        [for (final c in list) c.kind],
        [CredentialKind.github, CredentialKind.slack],
      );
      expect(response.body, isNot(contains('SECRETPART')));
      expect(response.body, isNot(contains('ghp_secret')));
    });

    test('narrows to a flavor', () async {
      await save(github());

      final one = await send('GET', '?flavor=default');
      final none = await send('GET', '?app=.&flavor=default');

      expect(CredentialsResponse.fromJson(one.json).credentials, hasLength(1));
      expect(CredentialsResponse.fromJson(none.json).credentials, hasLength(1));
    });

    test('answers 404 for an unknown flavor or project', () async {
      expect((await send('GET', '?flavor=nope')).statusCode, 404);
      expect(
        (await engine.request('/projects/prj_nope/credentials')).statusCode,
        404,
      );
    });

    test('answers 400 for an app without a flavor', () async {
      expect((await send('GET', '?app=apps/x')).statusCode, 400);
    });

    test('answers 401 without a token', () async {
      expect((await send('GET', '', token: '')).statusCode, 401);
    });
  });

  group('POST /projects/{id}/credentials/{id}/verify', () {
    late Credential saved;

    setUp(() async {
      saved = Credential.fromJson((await save(github())).json);
      engine.clock.advance(const Duration(days: 1));
    });

    test('checks again and answers the new status', () async {
      final response = await send('POST', '/${saved.id}/verify');

      expect(response.statusCode, 200);
      final credential = Credential.fromJson(response.json);
      expect(credential.status, CredentialStatus.verified);
      expect(credential.checkedAt, engine.clock.now());
    });

    test(
      'answers 200 with the refusal of a credential that went bad',
      () async {
        engine.credentialVerifiers[CredentialKind.github]!.answers.add(
          const VerificationResult.rejected('Revoked.', fix: 'Replace it.'),
        );

        final response = await send('POST', '/${saved.id}/verify');

        expect(response.statusCode, 200);
        final credential = Credential.fromJson(response.json);
        expect(credential.status, CredentialStatus.rejected);
        expect(credential.message, 'Revoked.');
        expect(credential.fix, 'Replace it.');
      },
    );

    test('answers 404 for an unknown credential', () async {
      expect((await send('POST', '/crd_nope/verify')).statusCode, 404);
    });

    test('answers 503 when the secrets are locked', () async {
      engine.credentialSecrets.failure = const SecretsLockedException('locked');

      expect((await send('POST', '/${saved.id}/verify')).statusCode, 503);
    });

    test('answers 401 without a token', () async {
      expect(
        (await send('POST', '/${saved.id}/verify', token: '')).statusCode,
        401,
      );
    });
  });

  group('DELETE /projects/{id}/credentials/{id}', () {
    test('deletes the reference and the secret', () async {
      final saved = Credential.fromJson(
        (await save({
          'kind': 'slack',
          'webhookUrl': 'https://hooks.slack.com/services/T/B/X',
        })).json,
      );

      final response = await send('DELETE', '/${saved.id}');

      expect(response.statusCode, 204);
      expect(await engine.credentialRepository.list(), isEmpty);
      expect(engine.credentialSecrets.values, isEmpty);
    });

    test('answers 404 for an unknown credential', () async {
      expect((await send('DELETE', '/crd_nope')).statusCode, 404);
    });

    test('answers 401 without a token', () async {
      expect((await send('DELETE', '/crd_x', token: '')).statusCode, 401);
    });
  });
}

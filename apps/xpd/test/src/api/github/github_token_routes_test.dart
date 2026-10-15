import 'dart:convert';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../helpers/test_engine.dart';

void main() {
  late TestEngine engine;
  late Map<DeviceTokenKind, String> secrets;

  setUp(() async {
    engine = await TestEngine.start();
    secrets = {
      DeviceTokenKind.app: engine.secret,
      for (final kind in [
        DeviceTokenKind.cli,
        DeviceTokenKind.mcp,
        DeviceTokenKind.runner,
      ])
        kind: (await engine.tokens.issue(
          name: '${kind.name} token',
          kind: kind,
        )).secret,
    };
  });

  tearDown(() => engine.close());

  FakeCredentialVerifier github() =>
      engine.credentialVerifiers[CredentialKind.github]!;

  String? stored() => engine.credentialSecrets.text(githubTokenSecretKey);

  Future<RawResponse> send(
    String method,
    String path, {
    DeviceTokenKind kind = DeviceTokenKind.app,
    Object? body,
    String? rawBody,
  }) => engine.request(
    path,
    method: method,
    token: secrets[kind],
    body: rawBody ?? (body == null ? null : jsonEncode(body)),
  );

  ErrorResponse errorOf(RawResponse response) =>
      ErrorResponse.fromJson(response.json);

  group('GET /github-token', () {
    test('says there is none', () async {
      final response = await send('GET', '/github-token');

      expect(response.statusCode, 200);
      expect(response.json, {'stored': false});
    });

    test('says who the token belongs to, never the token', () async {
      await engine.credentialSecrets.write(githubTokenSecretKey, 'ghp_secret');
      github().answers.add(const VerificationResult.verified(account: 'octo'));

      final response = await send('GET', '/github-token', kind: .mcp);

      expect(response.statusCode, 200);
      expect(
        GitHubTokenStatus.fromJson(response.json),
        const GitHubTokenStatus(
          stored: true,
          status: CredentialStatus.verified,
          login: 'octo',
        ),
      );
      expect(response.body, isNot(contains('ghp_secret')));
    });

    test('is not for runners', () async {
      final response = await send('GET', '/github-token', kind: .runner);

      expect(response.statusCode, 403);
    });
  });

  group('PUT /github-token', () {
    test('stores a token GitHub accepts', () async {
      github().answers.add(const VerificationResult.verified(account: 'octo'));

      final response = await send(
        'PUT',
        '/github-token',
        body: {'token': 'ghp_new'},
      );

      expect(response.statusCode, 200);
      expect(GitHubTokenStatus.fromJson(response.json).login, 'octo');
      expect(response.body, isNot(contains('ghp_new')));
      expect(stored(), 'ghp_new');
      expect(engine.masker.secrets, contains('ghp_new'));
    });

    test('answers 422 and stores nothing when GitHub refuses it', () async {
      github().answers.add(
        const VerificationResult.rejected(
          'GitHub refused the token.',
          fix: 'Save a new token.',
        ),
      );

      final response = await send(
        'PUT',
        '/github-token',
        body: {'token': 'ghp_bad'},
      );

      expect(response.statusCode, 422);
      expect(errorOf(response).error.code, ApiErrorCode.credentialRejected);
      expect(
        errorOf(response).error.message,
        'GitHub refused the token. Save a new token.',
      );
      expect(response.body, isNot(contains('ghp_bad')));
      expect(stored(), isNull);
    });

    test('answers 502 when GitHub cannot be reached', () async {
      github().answers.add(
        const VerificationResult.unreachable('GitHub is not reachable.'),
      );

      final response = await send(
        'PUT',
        '/github-token',
        body: {'token': 'ghp_new'},
      );

      expect(response.statusCode, 502);
      expect(errorOf(response).error.code, ApiErrorCode.upstreamError);
      expect(errorOf(response).error.message, contains('Nothing was stored.'));
      expect(stored(), isNull);
    });

    test('answers 400 for a body without a token string', () async {
      for (final body in [
        <String, Object>{},
        {'token': 42},
      ]) {
        final response = await send('PUT', '/github-token', body: body);

        expect(response.statusCode, 400, reason: '$body');
        expect(errorOf(response).error.code, ApiErrorCode.invalidRequest);
      }
      expect(github().checked, isEmpty);
    });

    test('answers 403 to an MCP token', () async {
      final response = await send(
        'PUT',
        '/github-token',
        kind: .mcp,
        body: {'token': 'ghp_new'},
      );

      expect(response.statusCode, 403);
      expect(errorOf(response).error.code, ApiErrorCode.forbidden);
      expect(stored(), isNull);
    });

    test('answers 503 when the secrets are locked', () async {
      engine.credentialSecrets.failure = const SecretsLockedException('locked');

      final response = await send(
        'PUT',
        '/github-token',
        body: {'token': 'ghp_new'},
      );

      expect(response.statusCode, 503);
      expect(errorOf(response).error.code, ApiErrorCode.secretsLocked);
    });
  });

  group('POST /github-token/import', () {
    test("stores the GitHub CLI's token", () async {
      final response = await send('POST', '/github-token/import', kind: .cli);

      expect(response.statusCode, 200);
      expect(
        GitHubTokenStatus.fromJson(response.json).status,
        CredentialStatus.verified,
      );
      expect(stored(), engine.githubCli.token);
    });

    test('answers 422 when gh gives no token', () async {
      engine.githubCli.error = const GitHubCliTokenException(
        'The GitHub CLI (gh) was not found.',
        fix: 'Install it.',
      );

      final response = await send('POST', '/github-token/import');

      expect(response.statusCode, 422);
      expect(
        errorOf(response).error.message,
        'The GitHub CLI (gh) was not found. Install it.',
      );
    });
  });

  group('DELETE /github-token', () {
    test('forgets the token', () async {
      await engine.credentialSecrets.write(githubTokenSecretKey, 'ghp_old');

      final response = await send('DELETE', '/github-token');

      expect(response.statusCode, 204);
      expect(stored(), isNull);
    });

    test('answers 403 to an MCP token', () async {
      await engine.credentialSecrets.write(githubTokenSecretKey, 'ghp_old');

      final response = await send('DELETE', '/github-token', kind: .mcp);

      expect(response.statusCode, 403);
      expect(stored(), 'ghp_old');
    });
  });
}

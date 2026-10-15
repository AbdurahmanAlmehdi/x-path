@Tags(['contract'])
library;

import 'dart:convert';

import 'package:test/test.dart';
import 'package:xp_api/testing.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../helpers/test_engine.dart';

/// Every response of the GitHub token endpoints is checked against
/// `openapi.yaml`.
void main() {
  late OpenApiContract contract;
  late TestEngine engine;
  late String mcp;

  setUpAll(() async => contract = await OpenApiContract.load());
  setUp(() async {
    engine = await TestEngine.start();
    mcp = (await engine.tokens.issue(
      name: 'agent',
      kind: DeviceTokenKind.mcp,
    )).secret;
  });
  tearDown(() => engine.close());

  FakeCredentialVerifier github() =>
      engine.credentialVerifiers[CredentialKind.github]!;

  Future<void> expectContract(
    String method,
    String path,
    int status, {
    String? token,
    Object? body,
  }) async {
    final response = await engine.request(
      path,
      method: method,
      token: token,
      body: body == null ? null : jsonEncode(body),
    );
    expect(response.statusCode, status, reason: response.body);
    contract.expectResponse(
      method: method,
      path: path,
      statusCode: response.statusCode,
      contentType: response.contentType,
      body: response.body,
    );
  }

  test('request bodies match their schemas', () {
    expect(
      contract.validateSchema('SetGitHubTokenRequest', {'token': 'ghp_x'}),
      isEmpty,
    );
    expect(
      contract.validateSchema('SetGitHubTokenRequest', {'token': ''}),
      isNotEmpty,
    );
  });

  test('GET /github-token 200, 401 and 503', () async {
    await expectContract('GET', '/github-token', 200);
    await engine.credentialSecrets.write(githubTokenSecretKey, 'ghp_x');
    github().answers.add(const VerificationResult.verified(account: 'octo'));
    await expectContract('GET', '/github-token', 200);
    github().answers.add(
      const VerificationResult.rejected('Refused.', fix: 'Save another.'),
    );
    await expectContract('GET', '/github-token', 200);
    await expectContract('GET', '/github-token', 401, token: '');
    engine.credentialSecrets.failure = const SecretsLockedException('locked');
    await expectContract('GET', '/github-token', 503);
  });

  test('PUT /github-token 200, 400, 401, 403, 422, 502 and 503', () async {
    const path = '/github-token';
    const body = {'token': 'ghp_x'};

    await expectContract('PUT', path, 200, body: body);
    await expectContract('PUT', path, 400, body: <String, Object>{});
    await expectContract('PUT', path, 401, token: '', body: body);
    await expectContract('PUT', path, 403, token: mcp, body: body);
    github().answers.add(const VerificationResult.rejected('Refused.'));
    await expectContract('PUT', path, 422, body: body);
    github().answers.add(const VerificationResult.unreachable('Offline.'));
    await expectContract('PUT', path, 502, body: body);
    engine.credentialSecrets.failure = const SecretsLockedException('locked');
    await expectContract('PUT', path, 503, body: body);
  });

  test('POST /github-token/import 200, 401, 403, 422 and 502', () async {
    const path = '/github-token/import';

    await expectContract('POST', path, 200);
    await expectContract('POST', path, 401, token: '');
    await expectContract('POST', path, 403, token: mcp);
    github().answers.add(const VerificationResult.unreachable('Offline.'));
    await expectContract('POST', path, 502);
    engine.githubCli.error = const GitHubCliTokenException('No gh.');
    await expectContract('POST', path, 422);
  });

  test('DELETE /github-token 204, 401 and 403', () async {
    await expectContract('DELETE', '/github-token', 204);
    await expectContract('DELETE', '/github-token', 401, token: '');
    await expectContract('DELETE', '/github-token', 403, token: mcp);
  });
}

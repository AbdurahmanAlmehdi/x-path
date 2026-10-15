import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';

import '../../helpers/runner_helpers.dart';
import '../../helpers/test_engine.dart';

/// ADR 0011: a `runner` token reaches the runner connection and the artifact
/// upload, and nothing else.
void main() {
  late RunnerClient client;

  setUp(() async => client = await RunnerClient.start());
  tearDown(() => client.close());

  Future<RawResponse> asRunner(String method, String path, {Object? body}) =>
      client.send(method, path, kind: DeviceTokenKind.runner, body: body);

  test('answers 403 with the reason to every other route', () async {
    for (final (method, path) in [
      ('GET', '/projects'),
      ('POST', '/projects'),
      ('GET', '/jobs/job_1'),
      ('POST', '/jobs/job_1/cancel'),
      ('GET', '/jobs/job_1/artifacts'),
      ('GET', '/runners'),
      ('POST', '/runners/pairing-tokens'),
      ('GET', '/approvals'),
      ('GET', '/releases/rel_1'),
      ('GET', '/storage'),
      ('GET', '/projects/prj_1/credentials'),
      ('GET', '/events'),
      ('GET', '/jobs/job_1/logs'),
      // The right path with the wrong method is not the runner's either.
      ('GET', '/runners/jobs/job_1/artifacts/app.apk'),
      ('POST', '/runners/connect'),
      ('POST', '/runners/bundle'),
      ('PUT', '/runners/connect'),
      // Nor a route that does not exist: the scope answers before routing.
      ('GET', '/nothing'),
    ]) {
      final response = await asRunner(
        method,
        path,
        body: method == 'GET' ? null : <String, Object>{},
      );

      expect(response.statusCode, 403, reason: '$method $path');
      final error = ErrorResponse.fromJson(response.json).error;
      expect(error.code, ApiErrorCode.forbidden, reason: '$method $path');
      expect(error.message, contains('A runner token reaches only'));
      expect(error.message, contains('GET /runners/bundle'));
      expect(error.message, contains('$method $path'));
    }
  });

  test('lets the connection through to the WebSocket check', () async {
    // Not an upgrade request: the route itself says so, with 426.
    final response = await asRunner('GET', '/runners/connect');

    expect(response.statusCode, isNot(403));
    expect(response.statusCode, 426);
  });

  test('lets the download of the bundle through to the route', () async {
    // No bundle was put there: the route answers 404, not the scope's 403.
    final response = await asRunner(
      'GET',
      '/runners/bundle?os=linux&arch=arm64',
    );

    expect(response.statusCode, isNot(403));
    expect(response.statusCode, 404);
  });

  test('lets the upload of an artifact through to the lease check', () async {
    // The runner holds no lease: the route answers 409, not the scope's 403.
    final response = await client.upload('job_1', 'app.apk', [
      1,
      2,
      3,
    ], leaseId: 'lse_1');

    expect(response.statusCode, isNot(403));
    expect(response.statusCode, 409);
  });

  test('leaves the other kinds of token alone', () async {
    for (final kind in [
      DeviceTokenKind.app,
      DeviceTokenKind.cli,
      DeviceTokenKind.mcp,
    ]) {
      final response = await client.send('GET', '/projects', kind: kind);

      expect(response.statusCode, 200, reason: kind.name);
    }
  });

  test('leaves the routes that need no token alone', () async {
    for (final path in ['/health', '/version']) {
      final response = await client.engine.request(path, token: '');

      expect(response.statusCode, 200, reason: path);
    }
  });

  test('does not read a runner token that is revoked as a runner', () async {
    await client.send('POST', '/runners/${client.runner.id}/revoke');

    final response = await client.send(
      'GET',
      '/projects',
      token: client.credential,
    );

    expect(response.statusCode, 401);
  });
}

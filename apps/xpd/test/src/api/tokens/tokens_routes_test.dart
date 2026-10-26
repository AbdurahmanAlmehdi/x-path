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

  group('POST /tokens', () {
    test('makes a cli token that then works, and shows it once', () async {
      final response = await send(
        'POST',
        '/tokens',
        body: {'name': '  xp on MacBook ', 'kind': 'cli'},
      );

      expect(response.statusCode, 201, reason: response.body);
      final created = CreatedToken.fromJson(response.json);
      expect(created.info.name, 'xp on MacBook');
      expect(created.info.kind, DeviceTokenKind.cli);
      expect(created.token, startsWith('xpt_'));
      final status = await engine.request('/status', token: created.token);
      expect(StatusResponse.fromJson(status.json).token, created.info);
    });

    test('makes an mcp token', () async {
      final response = await send(
        'POST',
        '/tokens',
        body: {'name': 'agent', 'kind': 'mcp'},
      );

      expect(
        CreatedToken.fromJson(response.json).info.kind,
        DeviceTokenKind.mcp,
      );
    });

    test('is for the app only', () async {
      for (final kind in [
        DeviceTokenKind.cli,
        DeviceTokenKind.mcp,
        DeviceTokenKind.runner,
      ]) {
        final response = await send(
          'POST',
          '/tokens',
          kind: kind,
          body: {'name': 'x', 'kind': 'cli'},
        );

        expect(response.statusCode, 403, reason: kind.name);
      }
    });

    test('refuses a blank name and an app or runner kind', () async {
      for (final body in [
        {'name': ' ', 'kind': 'cli'},
        {'kind': 'cli'},
        {'name': 'x', 'kind': 'app'},
        {'name': 'x', 'kind': 'runner'},
        {'name': 'x'},
      ]) {
        final response = await send('POST', '/tokens', body: body);

        expect(response.statusCode, 400, reason: '$body');
        expect(errorOf(response).error.code, ApiErrorCode.invalidRequest);
      }
      final malformed = await send('POST', '/tokens', rawBody: '[');
      expect(malformed.statusCode, 400);
    });
  });

  test('GET /status names the token that asks, never its secret, and the '
      'secrets', () async {
    final response = await send('GET', '/status', kind: DeviceTokenKind.mcp);

    expect(response.statusCode, 200);
    final status = StatusResponse.fromJson(response.json);
    expect(status.token.name, 'mcp token');
    expect(status.token.kind, DeviceTokenKind.mcp);
    expect(status.secretsLocked, isFalse);
    expect(response.body, isNot(contains(secrets[DeviceTokenKind.mcp])));

    engine.credentialSecrets.failure = const SecretsLockedException('locked');
    final locked = await send('GET', '/status');
    expect(StatusResponse.fromJson(locked.json).secretsLocked, isTrue);
  });

  test('GET /doctor answers what the engine found, not to runners', () async {
    final response = await send('GET', '/doctor', kind: DeviceTokenKind.mcp);

    expect(response.statusCode, 200, reason: response.body);
    final checks = DoctorResponse.fromJson(response.json).checks;
    expect(
      checks.first,
      const EngineCheck(
        name: 'ios-sign',
        state: CheckState.skipped,
        detail: 'not macOS',
        fix: 'run the engine on a Mac',
      ),
    );
    expect(
      [for (final check in checks) check.name],
      ['ios-sign', 'android', 'flutter', 'secrets', 'github', 'credentials'],
    );
    final runner = await send('GET', '/doctor', kind: DeviceTokenKind.runner);
    expect(runner.statusCode, 403);
  });
}

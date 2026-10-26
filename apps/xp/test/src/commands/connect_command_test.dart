import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:xp/src/config/xp_config.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_engine/xp_engine.dart' show SecretsLockedException;

import '../../helpers/test_env.dart';

void main() {
  late TestEnv env;

  setUp(() {
    // No engine or token in the environment: connect has to save them.
    env = TestEnv(
      environment: {
        engineUrlVariable: '',
        tokenVariable: '',
        mcpTokenVariable: '',
      },
    );
    when(() => env.client.version()).thenAnswer(
      (_) async => VersionResponse(version: '0.0.1', apiVersion: apiVersion),
    );
    when(() => env.client.health())
        .thenAnswer((_) async => const HealthResponse());
    when(() => env.client.listProjects()).thenAnswer((_) async => []);
  });
  tearDown(() => env.dispose());

  ApiException rejected() => const ApiException(
    'Bad token.',
    statusCode: 401,
    code: ApiErrorCode.unauthorized,
  );

  test('checks the engine and the token, then saves both', () async {
    await env.runOk(['connect', 'http://127.0.0.1:7480', '--token', 'c1']);

    expect(env.logger.successes.single, contains('127.0.0.1:7480'));
    expect(env.logger.successes.single, contains('cli token'));
    expect(env.vault.tokens, {DeviceTokenKind.cli: 'c1'});
    expect(
      File('${env.directory.path}/xp.json').readAsStringSync(),
      contains('http://127.0.0.1:7480'),
    );
    // The probe has no token; each token is tried on its own.
    expect(env.connections.map((c) => c.token), ['', 'c1']);
    verify(() => env.client.health()).called(1);
    expect(env.client.closed, 2);
  });

  test('saves the MCP token apart from the CLI token', () async {
    await env.runOk([
      'connect',
      'http://e:1',
      '--token',
      'c1',
      '--mcp-token',
      'm1',
    ]);

    expect(env.vault.tokens, {
      DeviceTokenKind.cli: 'c1',
      DeviceTokenKind.mcp: 'm1',
    });
    expect(env.logger.successes.single, contains('cli and mcp token'));
    expect(env.connections.map((c) => c.token), ['', 'c1', 'm1']);
  });

  test('takes a bare host and port', () async {
    await env.runOk(['connect', '127.0.0.1:7480', '-t', 'c1']);

    expect(env.connections.first.url, Uri.parse('http://127.0.0.1:7480'));
  });

  test('without a URL reuses the saved engine', () async {
    await env.config.saveEngineUrl(Uri.parse('http://saved:1'));

    await env.runOk(['connect', '--mcp-token', 'm1']);

    expect(env.connections.first.url, Uri.parse('http://saved:1'));
    expect(env.vault.tokens, {DeviceTokenKind.mcp: 'm1'});
  });

  test('without a URL or a saved engine is a usage error', () async {
    expect(await env.run(['connect', '--token', 'c1']), 64);
    expect(env.logger.errors.single, contains('<url>'));
  });

  test('without a token and a terminal is a usage error', () async {
    expect(await env.run(['connect', 'http://e:1']), 64);
    expect(env.logger.errors.single, contains('--token'));
    expect(env.vault.tokens, isEmpty);
  });

  test('without a token asks for it at the terminal', () async {
    env.prompt
      ..interactive = true
      ..answers.addAll([' c1 \n', '']);

    await env.runOk(['connect', 'http://e:1']);
    expect(env.vault.tokens, {DeviceTokenKind.cli: 'c1'});
    expect(env.prompt.questions.single, contains('token of this CLI'));

    expect(await env.run(['connect', 'http://e:1']), 64);
    expect(env.logger.errors.last, contains('No token'));
  });

  test('with a URL that is not an engine address is a usage error', () async {
    expect(await env.run(['connect', 'ftp://e', '--token', 'c1']), 64);
  });

  test('with two URLs is a usage error', () async {
    expect(await env.run(['connect', 'http://a', 'http://b', '-t', 'c']), 64);
  });

  test('refuses an engine that speaks another API', () async {
    when(() => env.client.version()).thenAnswer(
      (_) async => const VersionResponse(version: '9.0.0', apiVersion: '9'),
    );

    expect(await env.run(['connect', 'http://e:1', '-t', 'c1']), 69);

    expect(env.logger.errors.single, contains('API v9'));
    expect(env.vault.tokens, isEmpty);
    expect(File('${env.directory.path}/xp.json').existsSync(), isFalse);
  });

  test('refuses a token the engine rejects and saves nothing', () async {
    when(() => env.client.listProjects()).thenThrow(rejected());

    expect(
      await env.run(['connect', 'http://e:1', '-t', 'c1', '--mcp-token', 'm']),
      77,
    );

    expect(env.logger.errors.single, contains('cli token'));
    expect(env.vault.tokens, isEmpty);
    expect(File('${env.directory.path}/xp.json').existsSync(), isFalse);
  });

  test('reports a failure of the token check other than a rejection', () async {
    when(() => env.client.listProjects()).thenThrow(
      const ApiException('Oops', statusCode: 500, code: ApiErrorCode.internal),
    );

    expect(await env.run(['connect', 'http://e:1', '-t', 'c1']), 70);
  });

  test('reports an engine that cannot be reached', () async {
    when(() => env.client.version()).thenThrow(
      const ConnectionException('Cannot reach the engine at http://e:1.'),
    );

    expect(await env.run(['connect', 'http://e:1', '-t', 'c1']), 69);
    expect(env.logger.errors.single, contains('Cannot reach'));
  });

  test('says when the secret store is locked', () async {
    env.vault.failWith = const SecretsLockedException(
      'The Keychain is locked.',
    );

    expect(await env.run(['connect', 'http://e:1', '-t', 'c1']), 78);
    expect(env.logger.errors.single, contains('locked'));
  });

  test('never prints a token, not even with --verbose', () async {
    await env.runOk([
      '--verbose',
      'connect',
      'http://e:1',
      '--token',
      'secret-cli',
      '--mcp-token',
      'secret-mcp',
    ]);

    final everything = [
      ...env.logger.infos,
      ...env.logger.errors,
      ...env.logger.warnings,
      ...env.logger.successes,
      ...env.logger.details,
    ].join('\n');
    expect(everything, contains('- token: ***'));
    expect(everything, contains('- mcp-token: ***'));
    expect(everything, isNot(contains('secret-cli')));
    expect(everything, isNot(contains('secret-mcp')));
  });

  test('prints its usage', () async {
    expect(await env.run(['connect', '--help']), 0);
    expect(env.logger.out, contains('--mcp-token'));
  });
}

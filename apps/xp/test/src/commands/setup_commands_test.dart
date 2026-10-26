import 'dart:convert';
import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:xp/src/config/xp_config.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_engine/xp_engine.dart' show SecretsLockedException;

import '../../helpers/samples.dart';
import '../../helpers/test_env.dart';

final _token = TokenInfo(
  id: 'tok_1',
  name: 'xp on MacBook',
  kind: DeviceTokenKind.cli,
  createdAt: DateTime.utc(2026, 10, 25),
);

void main() {
  late TestEnv env;

  setUp(() {
    env = TestEnv();
    when(() => env.client.version()).thenAnswer(
      (_) async => VersionResponse(version: '1.6.0', apiVersion: apiVersion),
    );
    when(() => env.client.health())
        .thenAnswer((_) async => const HealthResponse());
    when(() => env.client.status()).thenAnswer(
      (_) async => StatusResponse(token: _token, secretsLocked: false),
    );
    when(() => env.client.listProjects()).thenAnswer((_) async => [project]);
  });
  tearDown(() => env.dispose());

  group('xp status', () {
    test(
      'shows the engine, the token and the secrets, with no project',
      () async {
        await env.runOk(['status']);

        expect(env.logger.out, '''
engine   http://engine:7480 runs xpd 1.6.0 (API v$apiVersion)
health   ok
token    "xp on MacBook" (cli)
secrets  unlocked''');
        verifyNever(() => env.client.doctor());
      },
    );

    test(
      'says the secrets are locked and names the project of the folder',
      () async {
        when(() => env.client.status()).thenAnswer(
          (_) async => StatusResponse(token: _token, secretsLocked: true),
        );
        env.remote = 'https://github.com/${project.fullName}.git';

        await env.runOk(['status']);

        expect(
          env.logger.out,
          contains('secrets  locked: jobs that need them wait.'),
        );
        expect(
          env.logger.out,
          contains('project  ${project.fullName} (this folder)'),
        );
      },
    );

    test('prints JSON', () async {
      await env.runOk(['status', '--json']);

      final json = jsonDecode(env.logger.out) as Map<String, dynamic>;
      expect(json['engine'], 'http://engine:7480');
      expect(json['token'], _token.toJson());
      expect(json['secretsLocked'], isFalse);
      expect(json.containsKey('project'), isFalse);
    });

    test('takes no argument', () async {
      expect(await env.run(['status', 'x']), 64);
    });
  });

  group('xp doctor', () {
    test("prints xp's checks, then the engine's own", () async {
      when(() => env.client.doctor()).thenAnswer(
        (_) async => const DoctorResponse([
          EngineCheck(name: 'flutter', state: CheckState.ok),
          EngineCheck(
            name: 'ios-sign',
            state: CheckState.missing,
            detail: 'no Xcode',
            fix: 'install Xcode',
          ),
        ]),
      );

      expect(await env.run(['doctor']), 1);

      expect(env.logger.infos, [
        'ok       config: the engine is at http://engine:7480',
        'ok       engine',
        'ok       token: "xp on MacBook" (cli)',
        'ok       flutter',
        'missing  ios-sign: no Xcode',
        '         Install Xcode.',
        'Something is missing: see the fixes above.',
      ]);
    });

    test('exits 0 when nothing is missing, and prints JSON', () async {
      when(() => env.client.doctor()).thenAnswer(
        (_) async => const DoctorResponse([
          EngineCheck(name: 'ssh x', state: CheckState.skipped),
        ]),
      );

      await env.runOk(['doctor', '--json']);

      final json = jsonDecode(env.logger.out) as Map<String, dynamic>;
      expect(json['healthy'], isTrue);
      expect((json['checks'] as List).last, {
        'name': 'ssh x',
        'state': 'skipped',
      });
    });

    test('without a saved engine says how to connect', () async {
      env = TestEnv(environment: {engineUrlVariable: ''});

      expect(await env.run(['doctor']), 1);

      expect(
        env.logger.infos.first,
        startsWith('missing  config: No engine is set.'),
      );
      expect(env.logger.infos[1], contains('Settings ▸ CLI and agents'));
    });

    test('says when the engine does not answer', () async {
      when(() => env.client.health())
          .thenThrow(const ConnectionException('refused'));

      expect(await env.run(['doctor']), 1);

      expect(
        env.logger.infos[1],
        'missing  engine: the engine does not answer: refused',
      );
    });

    test('says when the engine refuses the token', () async {
      when(() => env.client.status()).thenThrow(
        const ApiException(
          'No.',
          statusCode: 401,
          code: ApiErrorCode.unauthorized,
        ),
      );

      expect(await env.run(['doctor']), 1);

      expect(
        env.logger.infos,
        contains('missing  token: the engine refuses the token of xp'),
      );
      verifyNever(() => env.client.doctor());
    });

    test('lets other errors through', () async {
      when(() => env.client.status()).thenThrow(
        const ApiException(
          'Boom.',
          statusCode: 500,
          code: ApiErrorCode.internal,
        ),
      );

      expect(await env.run(['doctor']), isNot(0));
      expect(env.logger.errors.single, contains('Boom.'));
    });

    test('takes no argument', () async {
      expect(await env.run(['doctor', 'x']), 64);
    });
  });

  group('xp disconnect', () {
    test('forgets the saved engine and both tokens', () async {
      await env.config.saveEngineUrl(Uri.parse('http://saved:1'));
      env.vault.tokens
        ..[DeviceTokenKind.cli] = 'c'
        ..[DeviceTokenKind.mcp] = 'm';

      await env.runOk(['disconnect']);

      expect(
        env.logger.successes.single,
        'Forgot http://saved:1 and the saved tokens.',
      );
      expect(env.vault.tokens, isEmpty);
      expect(
        File('${env.directory.path}/xp.json').readAsStringSync(),
        isNot(contains('saved')),
      );
    });

    test('with nothing saved says so', () async {
      await env.runOk(['disconnect']);

      expect(
        env.logger.successes.single,
        'Forgot the saved tokens; no engine was saved.',
      );
    });

    test('says when the secret store is locked', () async {
      env.vault.failWith = const SecretsLockedException(
        'The Keychain is locked.',
      );

      expect(await env.run(['disconnect']), isNot(0));
      expect(
        env.logger.errors.single,
        contains('Unlock it to forget the tokens.'),
      );
    });

    test('takes no argument', () async {
      expect(await env.run(['disconnect', 'x']), 64);
    });
  });
}

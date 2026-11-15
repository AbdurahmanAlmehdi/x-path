import 'dart:convert';

import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';

import '../../helpers/test_env.dart';

void main() {
  late TestEnv env;

  setUp(() => env = TestEnv());
  tearDown(() => env.dispose());

  final local = Uri.parse('http://127.0.0.1:7480/sign-in#code=ABCD');

  test('opens the dashboard signed in, and says the link works once', () async {
    when(() => env.client.dashboardSignInUrl()).thenAnswer((_) async => local);

    await env.runOk(['dashboard']);

    expect(env.opened, [local]);
    expect(env.logger.out, contains('Opened the dashboard'));
    expect(env.logger.out, isNot(contains('ABCD')));
    expect(env.logger.warnings, isEmpty);
  });

  test('prints the link with --print, or when no browser opens', () async {
    when(() => env.client.dashboardSignInUrl()).thenAnswer((_) async => local);

    await env.runOk(['dashboard', '--print']);
    expect(env.opened, isEmpty);
    expect(env.logger.out, contains('$local'));

    env.logger.infos.clear();
    env.browserOpens = false;
    await env.runOk(['--json', 'dashboard']);
    expect(jsonDecode(env.logger.out), {'url': '$local', 'opened': false});
  });

  test('leaves the link out of --json once the browser opened it', () async {
    when(() => env.client.dashboardSignInUrl()).thenAnswer((_) async => local);

    await env.runOk(['--json', 'dashboard']);

    expect(env.opened, [local]);
    expect(jsonDecode(env.logger.out), {'opened': true});
  });

  test(
    'warns when a browser cannot sign in over plain HTTP from here',
    () async {
      when(() => env.client.dashboardSignInUrl()).thenAnswer(
        (_) async => Uri.parse('http://192.168.1.20:7480/sign-in#code=ABCD'),
      );

      await env.runOk(['dashboard']);

      expect(env.logger.warnings.single, contains('xp settings public-url'));
    },
  );

  test('takes no argument', () async {
    expect(await env.run(['dashboard', 'extra']), 64);
    verifyNever(() => env.client.dashboardSignInUrl());
  });

  test('passes on what the engine refuses', () async {
    when(() => env.client.dashboardSignInUrl()).thenThrow(
      const ApiException(
        'Only an admin issues sign-in codes for others.',
        statusCode: 403,
        code: ApiErrorCode.forbidden,
      ),
    );

    expect(await env.run(['dashboard']), isNot(0));
    expect(env.logger.errors.join('\n'), contains('Only an admin'));
  });
}

import 'dart:convert';

import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';

import '../../helpers/samples.dart' as sample;
import '../../helpers/test_env.dart';

void main() {
  late TestEnv env;

  setUp(() {
    env = TestEnv();
    when(() => env.client.baseUrl)
        .thenReturn(Uri.parse('http://127.0.0.1:7480/'));
  });
  tearDown(() => env.dispose());

  final token = PairingToken(
    token: 'xpp_secret',
    name: 'mac-mini',
    expiresAt: DateTime.utc(2026, 10, 14, 9, 15),
  );

  group('runners list', () {
    final online = Runner(
      id: 'rnr_2',
      name: 'AWS Instance',
      status: RunnerStatus.online,
      capabilities: const ['android', 'flutter'],
      slots: 2,
      jobIds: const ['job_1'],
      os: 'linux',
      arch: 'x64',
      version: '1.1.2',
      lastHeartbeat: DateTime.utc(2026, 10, 22, 14, 2),
      createdAt: DateTime.utc(2026, 10, 22, 9),
      missing: const [
        MissingCapability(
          capability: 'swift-linux',
          reason: 'no Swift: swift not found',
          fix: 'install Swift for Linux from swift.org',
        ),
      ],
    );

    test('shows each runner, and what it lacks under the table', () async {
      when(() => env.client.listRunners())
          .thenAnswer((_) async => [online, sample.runner]);

      await env.runOk(['runners', 'list']);

      final lines = env.logger.out.split('\n');
      expect(
        lines.first,
        'NAME          ID     STATUS  LAST SEEN             CAPABILITIES     '
        'SLOTS  JOBS   MACHINE',
      );
      expect(lines[1], startsWith('AWS Instance  rnr_2  busy    2026-10-22 '));
      expect(
        lines[1],
        contains(
          'android,flutter  1/2    job_1  linux x64 xp '
          '1.1.2',
        ),
      );
      expect(lines, hasLength(4));
      expect(
        lines.last,
        'AWS Instance: no swift-linux: no Swift: swift not found. Install '
        'Swift for Linux from swift.org.',
      );
      expect(env.logger.out, isNot(contains('mac-mini')));
    });

    test('--all shows the revoked runners too', () async {
      when(() => env.client.listRunners())
          .thenAnswer((_) async => [sample.runner]);

      await env.runOk(['runners', 'list', '--all']);

      expect(env.logger.out, contains('mac-mini'));
      expect(env.logger.out, contains('revoked'));
      expect(env.logger.out, contains('0/1    -     '));
    });

    test('says how to pair one when there is none', () async {
      when(() => env.client.listRunners()).thenAnswer((_) async => []);

      await env.runOk(['runners', 'list']);

      expect(env.logger.out, 'No runners. Pair one: xp runners pair <name>');
    });

    test('with --json prints the runners', () async {
      when(() => env.client.listRunners()).thenAnswer((_) async => [online]);

      await env.runOk(['--json', 'runners', 'list']);

      expect(jsonDecode(env.logger.out), [
        jsonDecode(jsonEncode(online.toJson())),
      ]);
    });

    test('takes no argument', () async {
      expect(await env.run(['runners', 'list', 'extra']), 64);
    });
  });

  group('runners url', () {
    test('shows the URL, or says none is set and how to set one', () async {
      when(() => env.client.runnerUrl()).thenAnswer(
        (_) async => const RunnerUrl(url: 'https://mac.tailnet.ts.net'),
      );
      await env.runOk(['runners', 'url']);
      expect(
        env.logger.out,
        'Runners reach the engine at https://mac.tailnet.ts.net.',
      );

      env.logger.infos.clear();
      when(() => env.client.runnerUrl())
          .thenAnswer((_) async => const RunnerUrl());
      await env.runOk(['runners', 'url']);
      expect(env.logger.out, contains('No runner URL is set'));
      expect(env.logger.out, contains('#reaching-the-engine'));
    });

    test('sets it, says paired runners keep theirs, and passes on the '
        'warning', () async {
      when(() => env.client.setRunnerUrl('http://a.example')).thenAnswer(
        (_) async => const RunnerUrl(
          url: 'http://a.example',
          warning: 'Plain http carries signing material.',
        ),
      );

      await env.runOk(['runners', 'url', 'http://a.example']);

      expect(env.logger.out, contains('at http://a.example.'));
      expect(env.logger.out, contains('pair them again to move them'));
      expect(
        env.logger.warnings.single,
        'Plain http carries signing material.',
      );
    });

    test('--clear forgets it; --json prints it', () async {
      when(() => env.client.setRunnerUrl(null))
          .thenAnswer((_) async => const RunnerUrl());

      await env.runOk(['--json', 'runners', 'url', '--clear']);

      expect(jsonDecode(env.logger.out), <String, dynamic>{});
    });

    test('takes a URL or --clear, not both or two URLs', () async {
      expect(await env.run(['runners', 'url', 'a', 'b']), 64);
      expect(await env.run(['runners', 'url', 'a', '--clear']), 64);
      verifyNever(() => env.client.setRunnerUrl(any()));
    });
  });

  group('runners pair', () {
    test('prints the token once, with when it expires', () async {
      when(() => env.client.createPairingToken('mac-mini'))
          .thenAnswer((_) async => token);

      await env.runOk(['runners', 'pair', 'mac-mini']);

      expect(env.logger.out, contains('"mac-mini"'));
      expect(env.logger.out, contains('xpp_secret'));
      expect(env.logger.out, contains('works once'));
      expect(env.logger.out, contains('2026-10-14 09:15 UTC (15 minutes)'));
    });

    test('prints the whole command with the runner URL', () async {
      when(() => env.client.createPairingToken('mac-mini')).thenAnswer(
        (_) async => PairingToken(
          token: 'xpp_secret',
          name: 'mac-mini',
          expiresAt: DateTime.utc(2026, 10, 14, 9, 15),
          engineUrl: 'https://mac.tailnet.ts.net',
        ),
      );

      await env.runOk(['runners', 'pair', 'mac-mini']);

      expect(
        env.logger.out,
        contains(
          'within 15 minutes:\n  xp runner pair --engine '
          'https://mac.tailnet.ts.net --token xpp_secret\n',
        ),
      );
      expect(env.logger.out, isNot(contains('only works on this machine')));
    });

    test('without a runner URL uses its own address, and warns when it is '
        'loopback', () async {
      when(() => env.client.createPairingToken('mac-mini'))
          .thenAnswer((_) async => token);

      await env.runOk(['runners', 'pair', 'mac-mini']);

      expect(
        env.logger.out,
        contains('xp runner pair --engine http://127.0.0.1:7480 --token'),
      );
      expect(
        env.logger.out,
        contains('Set the address runners use: xp runners url <url>'),
      );
      expect(
        env.logger.out,
        contains('docs/guide/runners.md#reaching-the-engine'),
      );

      env.logger.infos.clear();
      when(() => env.client.baseUrl)
          .thenReturn(Uri.parse('https://xpath.example.com'));
      await env.runOk(['runners', 'pair', 'mac-mini']);
      expect(
        env.logger.out,
        contains('--engine https://xpath.example.com --token'),
      );
      expect(env.logger.out, isNot(contains('only works on this machine')));
    });

    test('with --json prints the token', () async {
      when(() => env.client.createPairingToken('mac-mini'))
          .thenAnswer((_) async => token);

      await env.runOk(['--json', 'runners', 'pair', 'mac-mini']);

      expect(jsonDecode(env.logger.infos.single), token.toJson());
    });

    test('needs exactly one name', () async {
      expect(await env.run(['runners', 'pair']), 64);
      expect(await env.run(['runners', 'pair', 'a', 'b']), 64);
      verifyNever(() => env.client.createPairingToken(any()));
    });

    test('a token that may not is said so', () async {
      when(() => env.client.createPairingToken(any())).thenThrow(
        const ApiException(
          'An mcp token cannot pair a runner.',
          statusCode: 403,
          code: ApiErrorCode.forbidden,
        ),
      );

      final code = await env.run(['runners', 'pair', 'x']);

      expect(code, 77);
      expect(env.logger.errors.single, contains('Not allowed'));
    });

    test('a name that is taken is a conflict', () async {
      when(() => env.client.createPairingToken(any())).thenThrow(
        const ApiException(
          'A runner called "x" exists already.',
          statusCode: 409,
          code: ApiErrorCode.conflict,
        ),
      );

      expect(await env.run(['runners', 'pair', 'x']), 73);
    });
  });

  group('runners revoke', () {
    test('revokes by name', () async {
      when(() => env.client.listRunners())
          .thenAnswer((_) async => [sample.runner]);
      when(() => env.client.revokeRunner('rnr_1'))
          .thenAnswer((_) async => sample.runner);

      await env.runOk(['runners', 'revoke', 'mac-mini']);

      expect(env.logger.out, contains('Revoked the runner "mac-mini"'));
      expect(env.logger.out, contains('rnr_1'));
      expect(env.logger.out, contains('wait for a resume'));
    });

    test('revokes by id without asking for the list', () async {
      when(() => env.client.revokeRunner('rnr_1'))
          .thenAnswer((_) async => sample.runner);

      await env.runOk(['runners', 'revoke', 'rnr_1']);

      verifyNever(() => env.client.listRunners());
    });

    test('with --json prints the runner', () async {
      when(() => env.client.revokeRunner('rnr_1'))
          .thenAnswer((_) async => sample.runner);

      await env.runOk(['--json', 'runners', 'revoke', 'rnr_1']);

      final printed =
          jsonDecode(env.logger.infos.single) as Map<String, dynamic>;
      expect(printed['status'], 'revoked');
    });

    test('says when there is no such runner', () async {
      when(() => env.client.listRunners()).thenAnswer((_) async => []);

      final code = await env.run(['runners', 'revoke', 'nope']);

      expect(code, 66);
      expect(env.logger.errors.single, contains('No runner "nope"'));
      verifyNever(() => env.client.revokeRunner(any()));
    });

    test('needs exactly one runner', () async {
      expect(await env.run(['runners', 'revoke']), 64);
    });
  });
}

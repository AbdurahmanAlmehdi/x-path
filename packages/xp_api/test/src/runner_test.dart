import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';

void main() {
  final created = DateTime.utc(2026, 10, 14, 9);

  group('RunnerStatus', () {
    test('uses lower case on the wire', () {
      expect(RunnerStatus.values.map((status) => status.wire), [
        'offline',
        'online',
        'draining',
        'revoked',
      ]);
    });
  });

  group('RunnerActivity', () {
    Runner runner(RunnerStatus status, {List<String> jobs = const []}) =>
        Runner(
          id: 'rnr_1',
          name: 'aws',
          status: status,
          capabilities: const [],
          slots: 2,
          jobIds: jobs,
          createdAt: created,
        );

    test('reads the status and the jobs as the owner sees them', () {
      expect(runner(RunnerStatus.online).activity, RunnerActivity.idle);
      expect(
        runner(RunnerStatus.online, jobs: ['job_1']).activity,
        RunnerActivity.busy,
      );
      expect(runner(RunnerStatus.draining).activity, RunnerActivity.updating);
      expect(
        runner(RunnerStatus.offline, jobs: ['job_1']).activity,
        RunnerActivity.lost,
      );
      expect(runner(RunnerStatus.offline).activity, RunnerActivity.offline);
      expect(runner(RunnerStatus.revoked).activity, RunnerActivity.revoked);
    });
  });

  group('Runner', () {
    final minimal = Runner(
      id: 'rnr_1',
      name: 'mac-mini',
      status: RunnerStatus.offline,
      capabilities: const [],
      slots: 1,
      jobIds: const [],
      createdAt: created,
    );
    final full = Runner(
      id: 'rnr_1',
      name: 'mac-mini',
      status: RunnerStatus.online,
      capabilities: const ['flutter', 'ios-sign'],
      slots: 2,
      jobIds: const ['job_1'],
      os: 'macos',
      arch: 'arm64',
      version: '1.0.0',
      cores: 8,
      lastHeartbeat: created.add(const Duration(minutes: 1)),
      createdAt: created,
      revokedAt: created.add(const Duration(days: 1)),
      missing: const [
        MissingCapability(
          capability: 'android',
          reason: 'no JDK: java not found',
          fix: 'install JDK 17 or set JAVA_HOME',
        ),
      ],
    );

    test('leaves out what it lacks', () {
      expect(minimal.toJson().keys, {
        'id',
        'name',
        'status',
        'capabilities',
        'slots',
        'jobIds',
        'createdAt',
      });
    });

    test('round-trips through JSON', () {
      expect(Runner.fromJson(minimal.toJson()), minimal);
      expect(Runner.fromJson(full.toJson()), full);
      expect(full.toJson()['status'], 'online');
      expect(full.toJson()['missing'], [
        {
          'capability': 'android',
          'reason': 'no JDK: java not found',
          'fix': 'install JDK 17 or set JAVA_HOME',
        },
      ]);
    });
  });

  group('RunnersResponse', () {
    test('round-trips through JSON', () {
      final response = RunnersResponse([
        Runner(
          id: 'rnr_1',
          name: 'a',
          status: RunnerStatus.revoked,
          capabilities: const [],
          slots: 1,
          jobIds: const [],
          createdAt: created,
        ),
      ]);

      expect(RunnersResponse.fromJson(response.toJson()), response);
    });
  });

  group('isLoopbackHost', () {
    test('is this machine only', () {
      for (final host in [
        'localhost',
        'LOCALHOST',
        '127.0.0.1',
        '127.9.9.9',
        '::1',
      ]) {
        expect(isLoopbackHost(host), isTrue, reason: host);
      }
      for (final host in ['', 'mac.tailnet.ts.net', '100.64.0.1', '10.0.0.1']) {
        expect(isLoopbackHost(host), isFalse, reason: host);
      }
    });
  });

  group('PairingCommand', () {
    PairingToken token({String? engineUrl}) => PairingToken(
      token: 'xpp_1',
      name: 'aws',
      expiresAt: created,
      engineUrl: engineUrl,
    );

    test('names the runner URL the token carries', () {
      final command = PairingCommand.of(
        token(engineUrl: 'https://mac.tailnet.ts.net'),
        fallback: Uri.parse('http://127.0.0.1:7480'),
      );

      expect(
        command.text,
        'xp runner pair --engine https://mac.tailnet.ts.net --token xpp_1',
      );
      expect(command.onlyHere, isFalse);
    });

    test('a loopback runner URL the owner set is not called out', () {
      expect(
        PairingCommand.of(
          token(engineUrl: 'http://127.0.0.1:7480'),
          fallback: Uri.parse('http://127.0.0.1:7480'),
        ).onlyHere,
        isFalse,
      );
      expect(
        PairingCommand.of(
          token(),
          fallback: Uri.parse('http://127.0.0.1:7480'),
          runnerUrl: 'http://127.0.0.1:7480',
        ).onlyHere,
        isFalse,
      );
    });

    test('falls back to the client address, called out when loopback', () {
      final local = PairingCommand.of(
        token(),
        fallback: Uri.parse('http://127.0.0.1:7480/'),
      );
      final remote = PairingCommand.of(
        token(),
        fallback: Uri.parse('https://xpath.example.com'),
      );
      final set = PairingCommand.of(
        token(),
        fallback: Uri.parse('http://127.0.0.1:7480'),
        runnerUrl: 'https://mac.tailnet.ts.net',
      );

      expect(local.engine, 'http://127.0.0.1:7480');
      expect(local.onlyHere, isTrue);
      expect(remote.onlyHere, isFalse);
      expect(set.engine, 'https://mac.tailnet.ts.net');
      expect(
        local,
        PairingCommand.of(
          token(),
          fallback: Uri.parse('http://127.0.0.1:7480'),
        ),
      );
    });
  });

  group('runner URL', () {
    test('round-trips, leaving out what it lacks', () {
      const url = RunnerUrl(url: 'http://a.example', warning: 'Plain http.');

      expect(const RunnerUrl().toJson(), <String, dynamic>{});
      expect(RunnerUrl.fromJson(url.toJson()), url);
    });

    test('the request to set it needs the url key, null clears', () {
      const clear = SetRunnerUrlRequest(url: null);

      expect(clear.toJson(), {'url': null});
      expect(SetRunnerUrlRequest.fromJson(const {'url': null}), clear);
      expect(
        SetRunnerUrlRequest.fromJson(const {'url': 'https://a.example'}).url,
        'https://a.example',
      );
      expect(
        () => SetRunnerUrlRequest.fromJson(const {}),
        throwsA(isA<Exception>()),
      );
    });

    test('a pairing token carries it when set', () {
      final token = PairingToken(
        token: 'xpp_secret',
        name: 'mac-mini',
        expiresAt: created,
        engineUrl: 'https://mac.tailnet.ts.net',
      );

      expect(token.toJson()['engineUrl'], 'https://mac.tailnet.ts.net');
      expect(PairingToken.fromJson(token.toJson()), token);
    });
  });

  group('pairing', () {
    test('the request for a pairing token names the runner', () {
      const request = CreatePairingTokenRequest(name: 'mac-mini');

      expect(request.toJson(), {'name': 'mac-mini'});
      expect(CreatePairingTokenRequest.fromJson(request.toJson()), request);
    });

    test('a pairing token has a secret, a name and an expiry', () {
      final token = PairingToken(
        token: 'xpp_secret',
        name: 'mac-mini',
        expiresAt: created.add(const Duration(minutes: 15)),
      );

      expect(token.toJson(), {
        'token': 'xpp_secret',
        'name': 'mac-mini',
        'expiresAt': '2026-10-14T09:15:00.000Z',
      });
      expect(PairingToken.fromJson(token.toJson()), token);
    });

    test('the exchange takes the pairing token and returns the credential', () {
      const request = PairRunnerRequest(pairingToken: 'xpp_secret');
      final response = PairRunnerResponse(
        runner: Runner(
          id: 'rnr_1',
          name: 'mac-mini',
          status: RunnerStatus.offline,
          capabilities: const [],
          slots: 1,
          jobIds: const [],
          createdAt: created,
        ),
        token: 'xpt_secret',
      );

      expect(PairRunnerRequest.fromJson(request.toJson()), request);
      expect(PairRunnerResponse.fromJson(response.toJson()), response);
    });
  });
}

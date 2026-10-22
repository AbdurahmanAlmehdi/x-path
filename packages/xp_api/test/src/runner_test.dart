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

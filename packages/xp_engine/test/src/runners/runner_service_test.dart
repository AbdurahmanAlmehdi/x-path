import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/runner_harness.dart';

void main() {
  late RunnerHarness h;

  setUp(() async => h = await RunnerHarness.create());

  Future<DeviceToken> token(DeviceTokenKind kind) async =>
      (await h.tokens.issue(name: kind.name, kind: kind)).token;

  group('createPairingToken', () {
    test('is single use, lasts 15 minutes and keeps only a hash', () async {
      final made = await h.service.createPairingToken(
        name: '  mac-mini ',
        by: h.owner,
      );

      expect(made.token, matches(RegExp(r'^xpp_[A-Za-z0-9_-]{43}$')));
      expect(made.name, 'mac-mini');
      expect(made.expiresAt, h.clock.now().add(const Duration(minutes: 15)));
      final stored = (await h.pairing.findByHash(hashToken(made.token)))!;
      expect(stored.name, 'mac-mini');
      expect(stored.createdBy, h.owner.id);
      expect(stored.usedAt, isNull);
      expect(stored.hash, isNot(contains(made.token)));
      expect(stored.toString(), isNot(contains(made.token)));
    });

    test('is for the app and the cli', () async {
      await h.service.createPairingToken(
        name: 'a',
        by: await token(DeviceTokenKind.cli),
      );
      for (final kind in [DeviceTokenKind.mcp, DeviceTokenKind.runner]) {
        await expectLater(
          h.service.createPairingToken(name: 'b', by: await token(kind)),
          throwsA(
            isA<RunnerForbiddenException>().having(
              (e) => e.message,
              'message',
              contains('${kind.name} token cannot pair a runner'),
            ),
          ),
        );
      }
    });

    test('wants a plain name that is free', () async {
      for (final name in ['', '   ', '-x', '.x', 'a/b', 'x' * 65, 'é']) {
        await expectLater(
          h.service.createPairingToken(name: name, by: h.owner),
          throwsA(isA<RunnerInvalidException>()),
          reason: name,
        );
      }
      final made = await h.service.createPairingToken(
        name: 'Mac mini 2.x_y-z',
        by: h.owner,
      );
      await h.service.pair(made.token);

      await expectLater(
        h.service.createPairingToken(name: 'Mac mini 2.x_y-z', by: h.owner),
        throwsA(isA<RunnerNameTakenException>()),
      );
    });

    test('forgets the tokens that expired a day ago', () async {
      final old = await h.service.createPairingToken(name: 'a', by: h.owner);
      h.clock.advance(const Duration(days: 1, minutes: 16));

      await h.service.createPairingToken(name: 'b', by: h.owner);

      expect(await h.pairing.findByHash(hashToken(old.token)), isNull);
    });
  });

  group('pair', () {
    test('makes the runner and its credential, and tells', () async {
      final made = await h.service.createPairingToken(
        name: 'mac-mini',
        by: h.owner,
      );

      final paired = await h.service.pair(made.token);

      expect(paired.runner.name, 'mac-mini');
      expect(paired.runner.id, matches(RegExp(r'^rnr_[0-9a-f]{16}$')));
      expect(paired.runner.status, RunnerStatus.offline);
      expect(paired.runner.capabilities, isEmpty);
      expect(paired.runner.createdAt, h.clock.now());
      expect(paired.token, startsWith('xpt_'));
      final credential = (await h.tokens.authenticate(paired.token))!;
      expect(credential.kind, DeviceTokenKind.runner);
      expect(credential.name, 'mac-mini');
      final record = (await h.runners.get(paired.runner.id))!;
      expect(record.tokenId, credential.id);
      expect(await h.service.runnerFor(credential), record);
      expect(await h.eventsOf<RunnerPaired>(), [
        RunnerPaired(runnerId: paired.runner.id, name: 'mac-mini'),
      ]);
    });

    test('works once', () async {
      final made = await h.service.createPairingToken(name: 'a', by: h.owner);
      await h.service.pair(made.token);

      await expectLater(
        h.service.pair(made.token),
        throwsA(
          isA<PairingRejectedException>().having(
            (e) => e.message,
            'message',
            contains('used already'),
          ),
        ),
      );
      expect(await h.runners.list(), hasLength(1));
    });

    test('works for one of two that ask at once', () async {
      final made = await h.service.createPairingToken(name: 'a', by: h.owner);

      final results = await Future.wait([
        h.service
            .pair(made.token)
            .then<Object>((r) => r)
            .catchError((Object e) => e),
        h.service
            .pair(made.token)
            .then<Object>((r) => r)
            .catchError((Object e) => e),
      ]);

      expect(results.whereType<PairRunnerResponse>(), hasLength(1));
      expect(results.whereType<PairingRejectedException>(), hasLength(1));
      expect(await h.runners.list(), hasLength(1));
    });

    test('works for 15 minutes', () async {
      final made = await h.service.createPairingToken(name: 'a', by: h.owner);
      final late = await h.service.createPairingToken(name: 'b', by: h.owner);

      h.clock.advance(const Duration(minutes: 14, seconds: 59));
      await h.service.pair(made.token);
      h.clock.advance(const Duration(seconds: 1));

      await expectLater(
        h.service.pair(late.token),
        throwsA(
          isA<PairingRejectedException>().having(
            (e) => e.message,
            'message',
            contains('expired'),
          ),
        ),
      );
    });

    test('does not know what it did not make', () async {
      for (final secret in ['', 'xpp_nothing', 'xpt_${'A' * 43}', 'junk']) {
        await expectLater(
          h.service.pair(secret),
          throwsA(isA<PairingRejectedException>()),
          reason: secret,
        );
      }
    });

    test('stops when the name was taken in the meantime', () async {
      final first = await h.service.createPairingToken(name: 'a', by: h.owner);
      final second = await h.service.createPairingToken(name: 'a', by: h.owner);
      await h.service.pair(first.token);

      await expectLater(
        h.service.pair(second.token),
        throwsA(isA<RunnerNameTakenException>()),
      );
    });
  });

  group('list and get', () {
    test('describe each runner with where it is', () async {
      final online = await h.online(name: 'online');
      final offline = await h.pair('offline');
      final revoked = await h.pair('revoked');
      await h.service.revoke(revoked.id, by: h.owner);
      final jobId = await h.job(needs: ['ios-sign']);
      await h.scheduler.pump();

      final runners = await h.service.list();

      expect(runners.map((r) => (r.name, r.status)), [
        ('online', RunnerStatus.online),
        ('offline', RunnerStatus.offline),
        ('revoked', RunnerStatus.revoked),
      ]);
      expect(runners.first.jobIds, [jobId]);
      expect(runners.first.capabilities, ['flutter', 'ios-sign']);
      expect(runners.first.slots, 2);
      expect((await h.service.get(offline.id)).status, RunnerStatus.offline);
      expect((await h.service.get(online.id)).jobIds, [jobId]);
      expect((await h.service.get(revoked.id)).revokedAt, isNotNull);
    });

    test('get fails for a runner that is not there', () async {
      await expectLater(
        h.service.get('rnr_nobody'),
        throwsA(
          isA<RunnerNotFoundException>().having(
            (e) => e.id,
            'id',
            'rnr_nobody',
          ),
        ),
      );
    });
  });

  group('revoke', () {
    test('kills the credential and the connection, once', () async {
      final made = await h.service.createPairingToken(name: 'a', by: h.owner);
      final paired = await h.service.pair(made.token);
      final credential = (await h.tokens.authenticate(paired.token))!;
      final record = (await h.runners.get(paired.runner.id))!;
      final link = FakeRunnerLink();
      h.hub.connect(record, link);

      final revoked = await h.service.revoke(record.id, by: h.owner);
      h.clock.advance(const Duration(minutes: 1));
      final again = await h.service.revoke(record.id, by: h.owner);

      expect(revoked.status, RunnerStatus.revoked);
      expect(revoked.revokedAt, DateTime.utc(2026, 10, 13, 9));
      expect(again, revoked);
      expect(await h.tokens.authenticate(paired.token), isNull);
      expect(link.closeCode, runnerRevokedCloseCode);
      expect(await h.eventsOf<RunnerRevoked>(), hasLength(1));
      await expectLater(
        h.service.runnerFor(credential),
        throwsA(isA<RunnerForbiddenException>()),
      );
    });

    test('is for the app and the cli, and for runners that exist', () async {
      final runner = await h.pair();
      for (final kind in [DeviceTokenKind.mcp, DeviceTokenKind.runner]) {
        await expectLater(
          h.service.revoke(runner.id, by: await token(kind)),
          throwsA(isA<RunnerForbiddenException>()),
        );
      }
      await expectLater(
        h.service.revoke('rnr_nobody', by: h.owner),
        throwsA(isA<RunnerNotFoundException>()),
      );
      await h.service.revoke(runner.id, by: await token(DeviceTokenKind.cli));
      expect((await h.service.get(runner.id)).status, RunnerStatus.revoked);
    });
  });

  group('runnerFor', () {
    test('is for runner tokens that belong to a runner', () async {
      for (final kind in [
        DeviceTokenKind.app,
        DeviceTokenKind.cli,
        DeviceTokenKind.mcp,
      ]) {
        await expectLater(
          h.service.runnerFor(await token(kind)),
          throwsA(
            isA<RunnerForbiddenException>().having(
              (e) => e.message,
              'message',
              contains('this is a ${kind.name} token'),
            ),
          ),
        );
      }
      // A runner token made by hand is paired with nothing.
      await expectLater(
        h.service.runnerFor(await token(DeviceTokenKind.runner)),
        throwsA(
          isA<RunnerForbiddenException>().having(
            (e) => e.message,
            'message',
            contains('belongs to no runner'),
          ),
        ),
      );
    });
  });
}

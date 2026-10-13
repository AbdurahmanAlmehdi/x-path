import 'dart:math';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  late InMemoryDeviceTokenRepository repository;
  late ManualClock clock;
  late TokenService service;

  setUp(() {
    repository = InMemoryDeviceTokenRepository();
    clock = ManualClock(DateTime.utc(2026, 10, 13, 8));
    service = TokenService(tokens: repository, clock: clock);
  });

  group('hashToken', () {
    test('is the hex SHA-256 of the secret', () {
      expect(
        hashToken('abc'),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });
  });

  group('issue', () {
    test(
      'returns a prefixed 256-bit secret and stores only its hash',
      () async {
        final issued = await service.issue(
          name: 'Mac mini',
          kind: DeviceTokenKind.runner,
        );

        expect(issued.secret, matches(RegExp(r'^xpt_[A-Za-z0-9_-]{43}$')));
        expect(issued.token.hash, hashToken(issued.secret));
        expect(issued.token.name, 'Mac mini');
        expect(issued.token.kind, DeviceTokenKind.runner);
        expect(issued.token.createdAt, DateTime.utc(2026, 10, 13, 8));
        expect(issued.token.id, matches(RegExp(r'^tok_[0-9a-f]{16}$')));
        expect(issued.token.isRevoked, isFalse);

        final stored = await repository.list();
        expect(stored, [issued.token]);
        expect(stored.toString(), isNot(contains(issued.secret)));
      },
    );

    test('issues a different secret and id every time', () async {
      final a = await service.issue(name: 'a', kind: DeviceTokenKind.app);
      final b = await service.issue(name: 'b', kind: DeviceTokenKind.app);

      expect(a.secret, isNot(b.secret));
      expect(a.token.id, isNot(b.token.id));
    });

    test('trims the name', () async {
      final issued = await service.issue(
        name: '  Laptop \n',
        kind: DeviceTokenKind.cli,
      );

      expect(issued.token.name, 'Laptop');
    });

    test('rejects a blank name', () {
      expect(
        service.issue(name: '  ', kind: DeviceTokenKind.cli),
        throwsArgumentError,
      );
    });

    test('is deterministic for a seeded random source', () async {
      Future<String> secretFrom(int seed) async {
        final seeded = TokenService(
          tokens: InMemoryDeviceTokenRepository(),
          clock: clock,
          random: Random(seed),
        );
        return (await seeded.issue(
          name: 'n',
          kind: DeviceTokenKind.mcp,
        )).secret;
      }

      expect(await secretFrom(1), await secretFrom(1));
      expect(await secretFrom(1), isNot(await secretFrom(2)));
    });
  });

  group('authenticate', () {
    test('returns the token that the secret belongs to', () async {
      await service.issue(name: 'other', kind: DeviceTokenKind.app);
      final issued = await service.issue(name: 'me', kind: DeviceTokenKind.cli);

      expect(await service.authenticate(issued.secret), issued.token);
    });

    test('rejects a missing secret', () async {
      expect(await service.authenticate(null), isNull);
    });

    test('rejects a secret without the prefix', () async {
      expect(await service.authenticate('hunter2'), isNull);
    });

    test('rejects a well-formed secret that was never issued', () async {
      await service.issue(name: 'me', kind: DeviceTokenKind.cli);

      expect(await service.authenticate('xpt_${'A' * 43}'), isNull);
    });

    test('rejects a revoked token', () async {
      await repository.add(
        DeviceToken(
          id: 'tok_1',
          name: 'old',
          kind: DeviceTokenKind.app,
          hash: hashToken('xpt_revoked'),
          createdAt: DateTime.utc(2026),
          revokedAt: DateTime.utc(2026, 2),
        ),
      );

      expect(await service.authenticate('xpt_revoked'), isNull);
    });

    test('rejects a stored hash of the wrong length', () async {
      await repository.add(
        DeviceToken(
          id: 'tok_1',
          name: 'broken',
          kind: DeviceTokenKind.app,
          hash: 'abc',
          createdAt: DateTime.utc(2026),
        ),
      );

      expect(await service.authenticate('xpt_anything'), isNull);
    });
  });

  test('IssuedToken compares by value', () async {
    final issued = await service.issue(name: 'n', kind: DeviceTokenKind.app);

    expect(IssuedToken(token: issued.token, secret: issued.secret), issued);
  });
}

import 'dart:math';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/people.dart';

void main() {
  late InMemoryDeviceTokenRepository repository;
  late InMemoryPersonRepository people;
  late ManualClock clock;
  late TokenService service;

  setUp(() {
    repository = InMemoryDeviceTokenRepository();
    people = InMemoryPersonRepository([owner]);
    clock = ManualClock(DateTime.utc(2026, 10, 13, 8));
    service = TokenService(tokens: repository, people: people, clock: clock);
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
          people: people,
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

    test('gives a runner token no person', () async {
      final issued = await service.issue(
        name: 'builder',
        kind: DeviceTokenKind.runner,
      );

      expect(issued.token.personId, isNull);
      expect(issued.token.role, isNull);
    });

    test('refuses a person for a runner token', () {
      expect(
        service.issue(
          name: 'builder',
          kind: DeviceTokenKind.runner,
          personId: owner.id,
        ),
        throwsArgumentError,
      );
    });

    test('issues for the person it is given', () async {
      final sam = personWith(PersonRole.developer);
      await people.add(sam);

      final issued = await service.issue(
        name: 'xp',
        kind: DeviceTokenKind.cli,
        personId: sam.id,
      );

      expect(issued.token.personId, sam.id);
      expect(issued.token.person, sam);
      expect(issued.token.role, PersonRole.developer);
    });

    test('issues for the eldest active admin without a person', () async {
      await people.update(owner.copyWith(removedAt: DateTime.utc(2026, 2)));
      await people.add(personWith(PersonRole.releaser));
      final admin = personWith(PersonRole.admin);
      await people.add(admin);

      final issued = await service.issue(name: 'n', kind: DeviceTokenKind.app);

      expect(issued.token.personId, admin.id);
    });

    test('refuses a removed or unknown person, or no admin at all', () async {
      final gone = personWith(PersonRole.viewer)
          .copyWith(removedAt: DateTime.utc(2026, 2));
      await people.add(gone);

      for (final personId in [gone.id, 'per_nobody']) {
        await expectLater(
          service.issue(
            name: 'n',
            kind: DeviceTokenKind.cli,
            personId: personId,
          ),
          throwsArgumentError,
        );
      }
      await people.update(owner.copyWith(role: PersonRole.viewer));
      await expectLater(
        service.issue(name: 'n', kind: DeviceTokenKind.cli),
        throwsArgumentError,
      );
      expect(await repository.list(), isEmpty);
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

    test('reads the person as they are now', () async {
      final issued = await service.issue(name: 'me', kind: DeviceTokenKind.cli);
      final demoted = owner.copyWith(role: PersonRole.viewer);
      await people.update(demoted);

      final found = await service.authenticate(issued.secret);

      expect(found?.person, demoted);
      expect(found?.role, PersonRole.viewer);
    });

    test('rejects the token of a removed or missing person', () async {
      final issued = await service.issue(name: 'me', kind: DeviceTokenKind.cli);
      await people.update(owner.copyWith(removedAt: DateTime.utc(2026, 2)));

      expect(await service.authenticate(issued.secret), isNull);

      final orphan = TokenService(
        tokens: repository,
        people: InMemoryPersonRepository(),
        clock: clock,
      );
      expect(await orphan.authenticate(issued.secret), isNull);
    });

    test('returns a runner token without a person', () async {
      final issued = await service.issue(
        name: 'builder',
        kind: DeviceTokenKind.runner,
      );

      expect(await service.authenticate(issued.secret), issued.token);
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

  group('issueWeb', () {
    test('issues an 8-hour web token for the person', () async {
      final issued = await service.issueWeb(personId: owner.id);

      expect(issued.token.kind, DeviceTokenKind.web);
      expect(issued.token.name, 'Browser');
      expect(issued.token.personId, owner.id);
      expect(issued.token.person, owner);
      expect(
        issued.token.expiresAt,
        DateTime.utc(2026, 10, 13, 8).add(TokenService.webSessionLifetime),
      );
      expect(await repository.list(), [issued.token]);
    });

    test('refuses a removed or unknown person', () async {
      await people.add(
        personWith(PersonRole.viewer).copyWith(removedAt: clock.now()),
      );

      expect(service.issueWeb(personId: 'per_viewer'), throwsArgumentError);
      expect(service.issueWeb(personId: 'per_nope'), throwsArgumentError);
    });

    test('stops authenticating and being listed once it expires', () async {
      final issued = await service.issueWeb(personId: owner.id);
      final app = await service.issue(name: 'a', kind: DeviceTokenKind.app);
      clock.advance(const Duration(hours: 7, minutes: 59));

      expect(await service.authenticate(issued.secret), isNotNull);
      expect(await service.listFor(app.token.withPerson(owner)), hasLength(2));

      clock.advance(const Duration(minutes: 1));

      expect(await service.authenticate(issued.secret), isNull);
      expect(await service.listFor(app.token.withPerson(owner)), [app.token]);
    });
  });

  group('revocations', () {
    test('tells the id of each token revoked, and only then', () async {
      final revoked = <String>[];
      service.revocations.listen(revoked.add);
      final a = await service.issue(name: 'a', kind: DeviceTokenKind.app);
      final b = await service.issue(name: 'b', kind: DeviceTokenKind.cli);
      final sam = personWith(PersonRole.developer);
      await people.add(sam);
      final c = await service.issue(
        name: 'c',
        kind: DeviceTokenKind.cli,
        personId: sam.id,
      );

      await service.revoke(a.token.id);
      await service.revoke(a.token.id);
      await service.revoke('tok_nope');
      await service.revokeAllOf(owner.id);
      await service.revokeFor(c.token.withPerson(sam), c.token.id);

      expect(revoked, [a.token.id, b.token.id, c.token.id]);
    });
  });

  group('revoke', () {
    test('stops the token from authenticating, once', () async {
      final issued = await service.issue(
        name: 'Mac mini',
        kind: DeviceTokenKind.runner,
      );
      clock.advance(const Duration(minutes: 5));

      expect(await service.revoke(issued.token.id), isTrue);

      expect(await service.authenticate(issued.secret), isNull);
      final stored = (await repository.list()).single;
      expect(stored.revokedAt, DateTime.utc(2026, 10, 13, 8, 5));
      expect(stored.name, 'Mac mini');
      expect(stored.kind, DeviceTokenKind.runner);
      expect(await service.revoke(issued.token.id), isFalse);
    });

    test('knows no token it was not given', () async {
      expect(await service.revoke('tok_nope'), isFalse);
    });
  });

  group('revokeAllOf', () {
    test(
      "revokes every valid token of the person, and no one else's",
      () async {
        final sam = personWith(PersonRole.developer);
        await people.add(sam);
        final mine = [
          await service.issue(name: 'a', kind: DeviceTokenKind.app),
          await service.issue(name: 'b', kind: DeviceTokenKind.mcp),
        ];
        final theirs = await service.issue(
          name: 'c',
          kind: DeviceTokenKind.cli,
          personId: sam.id,
        );
        final runner = await service.issue(
          name: 'd',
          kind: DeviceTokenKind.runner,
        );
        await service.revoke(mine.first.token.id);
        clock.advance(const Duration(minutes: 1));

        expect(await service.revokeAllOf(owner.id), 1);

        for (final issued in mine) {
          expect(await service.authenticate(issued.secret), isNull);
        }
        expect(await service.authenticate(theirs.secret), isNotNull);
        expect(await service.authenticate(runner.secret), isNotNull);
        final stored = {for (final t in await repository.list()) t.name: t};
        expect(stored['b']!.revokedAt, DateTime.utc(2026, 10, 13, 8, 1));
        expect(stored['a']!.revokedAt, DateTime.utc(2026, 10, 13, 8));
      },
    );
  });

  group('listFor and revokeFor', () {
    late Person sam;
    late IssuedToken ownerApp;
    late IssuedToken ownerMcp;
    late IssuedToken samCli;

    setUp(() async {
      sam = personWith(PersonRole.developer);
      await people.add(sam);
      ownerApp = await service.issue(name: 'a', kind: DeviceTokenKind.app);
      ownerMcp = await service.issue(name: 'b', kind: DeviceTokenKind.mcp);
      samCli = await service.issue(
        name: 'c',
        kind: DeviceTokenKind.cli,
        personId: sam.id,
      );
      await service.issue(name: 'd', kind: DeviceTokenKind.runner);
      final revoked = await service.issue(
        name: 'e',
        kind: DeviceTokenKind.cli,
        personId: sam.id,
      );
      await service.revoke(revoked.token.id);
    });

    Future<DeviceToken> asker(IssuedToken issued) async =>
        (await service.authenticate(issued.secret))!;

    List<String> names(List<DeviceToken> tokens) => [
      for (final token in tokens) token.name,
    ];

    test("an admin's app token sees every person's valid tokens", () async {
      expect(names(await service.listFor(await asker(ownerApp))), [
        'a',
        'b',
        'c',
      ]);
    });

    test('anyone else sees the valid tokens of their own person', () async {
      expect(names(await service.listFor(await asker(samCli))), ['c']);
    });

    test("an agent's mcp token neither lists nor revokes tokens, even its "
        "admin's", () async {
      final agent = await asker(ownerMcp);
      final refused = isA<TokenForbiddenException>()
          .having(
            (e) => e.message,
            'message',
            'An mcp token cannot list or revoke tokens: only the app, `xp` '
                'or the web dashboard do.',
          )
          .having((e) => '$e', 'toString', contains('TokenForbidden'));

      await expectLater(service.listFor(agent), throwsA(refused));
      await expectLater(
        service.revokeFor(agent, ownerApp.token.id),
        throwsA(refused),
      );
      await expectLater(
        service.revokeFor(agent, ownerMcp.token.id),
        throwsA(refused),
      );
      expect(await service.authenticate(ownerApp.secret), isNotNull);
    });

    test('revokes a token the asker sees', () async {
      await service.revokeFor(await asker(ownerApp), samCli.token.id);

      expect(await service.authenticate(samCli.secret), isNull);
    });

    test(
      "refuses a token the asker does not see, as if it weren't there",
      () async {
        final sam = await asker(samCli);
        await expectLater(
          service.revokeFor(sam, ownerApp.token.id),
          throwsA(
            isA<TokenNotFoundException>()
                .having((e) => e.id, 'id', ownerApp.token.id)
                .having((e) => e.message, 'message', contains('no token'))
                .having((e) => '$e', 'toString', contains('TokenNotFound')),
          ),
        );
        expect(await service.authenticate(ownerApp.secret), isNotNull);
      },
    );
  });

  group('issueFor', () {
    late Person sam;

    setUp(() async {
      sam = personWith(PersonRole.viewer);
      await people.add(sam);
    });

    Future<DeviceToken> tokenOf(DeviceTokenKind kind, Person person) async {
      final issued = await service.issue(
        name: kind.name,
        kind: kind,
        personId: person.id,
      );
      return (await service.authenticate(issued.secret))!;
    }

    test('lets an app or web token of any role make a cli or mcp token for '
        'its person', () async {
      for (final creator in [DeviceTokenKind.app, DeviceTokenKind.web]) {
        for (final kind in AccessPolicy.mintableKinds) {
          final issued = await service.issueFor(
            await tokenOf(creator, sam),
            name: ' laptop ',
            kind: kind,
          );

          expect(issued.token.kind, kind);
          expect(issued.token.personId, sam.id);
          expect(issued.token.name, 'laptop');
          expect(await service.authenticate(issued.secret), isNotNull);
        }
      }
    });

    test('refuses a cli or mcp creator', () async {
      for (final creator in [DeviceTokenKind.cli, DeviceTokenKind.mcp]) {
        await expectLater(
          service.issueFor(
            await tokenOf(creator, owner),
            name: 'n',
            kind: DeviceTokenKind.cli,
          ),
          throwsA(
            isA<TokenForbiddenException>().having(
              (e) => e.message,
              'message',
              startsWith('Only the app and the web dashboard make tokens'),
            ),
          ),
        );
      }
    });

    test('makes no app, runner or web token', () async {
      for (final kind in [
        DeviceTokenKind.app,
        DeviceTokenKind.runner,
        DeviceTokenKind.web,
      ]) {
        await expectLater(
          service.issueFor(
            await tokenOf(DeviceTokenKind.app, owner),
            name: 'n',
            kind: kind,
          ),
          throwsA(isA<TokenForbiddenException>()),
          reason: kind.name,
        );
      }
      final app = await tokenOf(DeviceTokenKind.app, owner);
      await expectLater(
        service.issueFor(app, name: 'n', kind: DeviceTokenKind.app),
        throwsA(
          isA<TokenForbiddenException>().having(
            (e) => e.message,
            'message',
            endsWith('An app token may not make an app token.'),
          ),
        ),
      );
    });
  });

  group('purgeEndedWebTokens', () {
    test('deletes the web tokens that ended a day ago or more', () async {
      final expired = await service.issueWeb(personId: owner.id);
      final revoked = await service.issueWeb(personId: owner.id);
      await service.revoke(revoked.token.id);
      final app = await service.issue(name: 'app', kind: DeviceTokenKind.app);
      await service.revoke(app.token.id);
      clock.advance(
        TokenService.webSessionLifetime + TokenService.endedWebTokenGrace,
      );
      final fresh = await service.issueWeb(personId: owner.id);
      clock.advance(const Duration(seconds: 1));

      expect(await service.purgeEndedWebTokens(), 2);

      expect((await repository.list()).map((t) => t.id), [
        app.token.id,
        fresh.token.id,
      ]);
      expect(expired.token.id, isNot(fresh.token.id));
    });
  });

  group('close', () {
    test('ends revocations, and revoking still works after', () async {
      final done = service.revocations.toList();
      final issued = await service.issue(name: 'a', kind: DeviceTokenKind.app);

      await service.close();

      expect(await done, isEmpty);
      expect(await service.revoke(issued.token.id), isTrue);
      expect(await service.revokeAllOf(owner.id), 0);
    });
  });

  test('IssuedToken compares by value', () async {
    final issued = await service.issue(name: 'n', kind: DeviceTokenKind.app);

    expect(IssuedToken(token: issued.token, secret: issued.secret), issued);
  });
}

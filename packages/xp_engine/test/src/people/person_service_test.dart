import 'dart:math';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/approval_harness.dart';
import '../../helpers/people.dart';

void main() {
  late InMemoryPersonRepository people;
  late InMemoryDeviceTokenRepository tokenRepository;
  late TokenService tokens;
  late ManualClock clock;
  late PersonService service;

  setUp(() {
    people = InMemoryPersonRepository([owner]);
    tokenRepository = InMemoryDeviceTokenRepository();
    clock = ManualClock(DateTime.utc(2026, 11, 13, 9));
    tokens = TokenService(
      tokens: tokenRepository,
      people: people,
      clock: clock,
    );
    service = PersonService(
      people: people,
      tokens: tokens,
      clock: clock,
      random: Random(1),
    );
  });

  group('create', () {
    test('adds an active person with a fresh id and a trimmed name', () async {
      final sam = await service.create(
        name: '  Sam ',
        role: PersonRole.releaser,
        by: null,
      );

      expect(sam.id, matches(RegExp(r'^per_[0-9a-f]{16}$')));
      expect(sam.name, 'Sam');
      expect(sam.role, PersonRole.releaser);
      expect(sam.createdAt, DateTime.utc(2026, 11, 13, 9));
      expect(sam.isRemoved, isFalse);
      expect(await service.get(sam.id), sam);
      expect(await service.list(), [owner, sam]);
    });

    test('makes ids from a secure random source by default', () async {
      final secure = PersonService(
        people: people,
        tokens: tokens,
        clock: clock,
      );

      final a = await secure.create(
        name: 'A',
        role: PersonRole.viewer,
        by: null,
      );
      final b = await secure.create(
        name: 'B',
        role: PersonRole.viewer,
        by: null,
      );

      expect(a.id, matches(RegExp(r'^per_[0-9a-f]{16}$')));
      expect(a.id, isNot(b.id));
    });

    test('refuses a blank or too long name', () async {
      for (final name in ['  ', 'x' * (maxPersonNameLength + 1)]) {
        await expectLater(
          service.create(name: name, role: PersonRole.viewer, by: null),
          throwsA(isA<PersonRequestException>()),
        );
      }
      expect(await service.list(), [owner]);
    });

    test('refuses the name of an active person, ignoring case', () async {
      await expectLater(
        service.create(name: 'OWNER', role: PersonRole.viewer, by: null),
        throwsA(
          isA<PersonConflictException>().having(
            (error) => error.message,
            'message',
            'Someone is called OWNER already.',
          ),
        ),
      );
    });

    test('takes the name of a removed person', () async {
      final sam = await service.create(
        name: 'Sam',
        role: PersonRole.viewer,
        by: null,
      );
      await service.remove(sam.id, by: null);

      final again = await service.create(
        name: 'Sam',
        role: PersonRole.viewer,
        by: null,
      );

      expect(again.id, isNot(sam.id));
    });
  });

  group('get', () {
    test('finds a removed person too', () async {
      final sam = await service.create(
        name: 'Sam',
        role: PersonRole.viewer,
        by: null,
      );
      await service.remove(sam.id, by: null);

      expect((await service.get(sam.id)).isRemoved, isTrue);
    });

    test('throws for an unknown id', () {
      expect(
        service.get('per_nobody'),
        throwsA(isA<PersonNotFoundException>()),
      );
    });
  });

  group('update', () {
    test('renames an active person', () async {
      final renamed = await service.update(owner.id, name: ' Abdu ', by: null);

      expect(renamed, owner.copyWith(name: 'Abdu'));
      expect(await service.get(owner.id), renamed);
    });

    test('lets a person keep their name in another case', () async {
      expect(
        (await service.update(owner.id, name: 'OWNER', by: null)).name,
        'OWNER',
      );
    });

    test("refuses another active person's name", () async {
      await service.create(name: 'Sam', role: PersonRole.viewer, by: null);

      await expectLater(
        service.update(owner.id, name: 'sam', by: null),
        throwsA(isA<PersonConflictException>()),
      );
    });

    test('refuses an unknown or removed person', () async {
      final sam = await service.create(
        name: 'Sam',
        role: PersonRole.viewer,
        by: null,
      );
      await service.remove(sam.id, by: null);

      for (final id in ['per_nobody', sam.id]) {
        await expectLater(
          service.update(id, name: 'New', by: null),
          throwsA(
            isA<PersonNotFoundException>().having(
              (error) => error.id,
              'id',
              id,
            ),
          ),
        );
      }
    });
  });

  group('update of the name and the role together', () {
    test('changes both in one write', () async {
      final sam = await service.create(
        name: 'Sam',
        role: PersonRole.viewer,
        by: null,
      );

      final changed = await service.update(
        sam.id,
        name: 'Samira',
        role: PersonRole.releaser,
        by: null,
      );

      expect(changed.name, 'Samira');
      expect(changed.role, PersonRole.releaser);
      expect(await service.get(sam.id), changed);
    });

    test('keeps the name when the role is refused', () async {
      await expectLater(
        service.update(
          owner.id,
          name: 'Abdu',
          role: PersonRole.viewer,
          by: null,
        ),
        throwsA(isA<PersonConflictException>()),
      );

      expect(await service.get(owner.id), owner);
    });

    test('keeps the role when the name is refused', () async {
      final sam = await service.create(
        name: 'Sam',
        role: PersonRole.admin,
        by: null,
      );

      await expectLater(
        service.update(
          sam.id,
          name: 'owner',
          role: PersonRole.viewer,
          by: null,
        ),
        throwsA(isA<PersonConflictException>()),
      );

      expect((await service.get(sam.id)).role, PersonRole.admin);
    });

    test('changes nothing without a name or a role', () async {
      expect(await service.update(owner.id, by: null), owner);
    });
  });

  group('findActive', () {
    test('finds an active person by id, or by name ignoring case', () async {
      final sam = await service.create(
        name: 'Sam',
        role: PersonRole.viewer,
        by: null,
      );

      expect(await service.findActive(sam.id), sam);
      expect(await service.findActive(' sAM '), sam);
      expect(await service.findActive('per_owner'), owner);
    });

    test('finds no one for an unknown or removed person', () async {
      final sam = await service.create(
        name: 'Sam',
        role: PersonRole.viewer,
        by: null,
      );
      await service.remove(sam.id, by: null);

      expect(await service.findActive('Sam'), isNull);
      expect(await service.findActive(sam.id), isNull);
      expect(await service.findActive('Nobody'), isNull);
    });

    test("prefers a person's id to another's name", () async {
      final sam = await service.create(
        name: 'Sam',
        role: PersonRole.viewer,
        by: null,
      );
      await service.create(name: sam.id, role: PersonRole.viewer, by: null);

      expect(await service.findActive(sam.id), sam);
    });
  });

  group('who may change people', () {
    test('an admin token may', () async {
      final admin = tokenOf(DeviceTokenKind.app);

      final sam = await service.create(
        name: 'Sam',
        role: PersonRole.viewer,
        by: admin,
      );
      await service.update(sam.id, role: PersonRole.developer, by: admin);
      expect((await service.remove(sam.id, by: admin)).isRemoved, isTrue);
    });

    test('a token below admin, or an agent, may not, and nothing '
        'changes', () async {
      final sam = await service.create(
        name: 'Sam',
        role: PersonRole.viewer,
        by: null,
      );
      final refused = [
        tokenOf(DeviceTokenKind.cli, role: PersonRole.releaser),
        tokenOf(DeviceTokenKind.mcp),
        tokenOf(DeviceTokenKind.runner),
      ];

      for (final by in refused) {
        await expectLater(
          service.create(name: 'Eve', role: PersonRole.admin, by: by),
          throwsA(isA<PersonForbiddenException>()),
        );
        await expectLater(
          service.update(sam.id, role: PersonRole.admin, by: by),
          throwsA(isA<PersonForbiddenException>()),
        );
        await expectLater(
          service.remove(sam.id, by: by),
          throwsA(isA<PersonForbiddenException>()),
        );
      }
      expect(await service.list(), [owner, sam]);
      await expectLater(
        service.update(
          sam.id,
          role: PersonRole.admin,
          by: tokenOf(DeviceTokenKind.cli, role: PersonRole.viewer),
        ),
        throwsA(
          isA<PersonForbiddenException>().having(
            (error) => error.message,
            'message',
            'A viewer cannot change a person: it takes the admin role or '
                'higher.',
          ),
        ),
      );
    });
  });

  group('update of the role', () {
    test('changes the role, which applies to the next request', () async {
      final sam = await service.create(
        name: 'Sam',
        role: PersonRole.admin,
        by: null,
      );
      final issued = await tokens.issue(
        name: 'xp',
        kind: DeviceTokenKind.cli,
        personId: sam.id,
      );

      final changed = await service.update(
        sam.id,
        role: PersonRole.viewer,
        by: null,
      );

      expect(changed.role, PersonRole.viewer);
      expect(
        (await tokens.authenticate(issued.secret))?.role,
        PersonRole.viewer,
      );
    });

    test('refuses to demote the last admin', () async {
      await service.create(name: 'Sam', role: PersonRole.releaser, by: null);

      await expectLater(
        service.update(owner.id, role: PersonRole.releaser, by: null),
        throwsA(
          isA<PersonConflictException>().having(
            (error) => error.message,
            'message',
            'Cannot demote Owner: they are the last admin. Make someone else '
                'an admin first.',
          ),
        ),
      );
      expect((await service.get(owner.id)).role, PersonRole.admin);
    });

    test('keeps the last admin an admin', () async {
      expect(
        await service.update(owner.id, role: PersonRole.admin, by: null),
        owner,
      );
    });

    test('demotes an admin while another is left', () async {
      await service.create(name: 'Sam', role: PersonRole.admin, by: null);

      expect(
        (await service.update(
          owner.id,
          role: PersonRole.developer,
          by: null,
        )).role,
        PersonRole.developer,
      );
    });

    test(
      'lets only one of two concurrent demotions of two admins pass',
      () async {
        final sam = await service.create(
          name: 'Sam',
          role: PersonRole.admin,
          by: null,
        );

        final results = await Future.wait([
          for (final id in [owner.id, sam.id])
            service
                .update(id, role: PersonRole.viewer, by: null)
                .then<Object>((person) => person, onError: (Object e) => e),
        ]);

        expect(results.whereType<Person>(), hasLength(1));
        expect(results.whereType<PersonConflictException>(), hasLength(1));
        final admins = (await service.list()).where(
          (p) => p.role == PersonRole.admin,
        );
        expect(admins, hasLength(1));
      },
    );
  });

  group('remove', () {
    test('removes the person and revokes every token they have', () async {
      final sam = await service.create(
        name: 'Sam',
        role: PersonRole.developer,
        by: null,
      );
      final theirs = await tokens.issue(
        name: 'xp',
        kind: DeviceTokenKind.cli,
        personId: sam.id,
      );
      final mine = await tokens.issue(name: 'app', kind: DeviceTokenKind.app);
      clock.advance(const Duration(minutes: 1));

      final removed = await service.remove(sam.id, by: null);

      expect(removed.removedAt, DateTime.utc(2026, 11, 13, 9, 1));
      expect(await service.get(sam.id), removed);
      expect(await tokens.authenticate(theirs.secret), isNull);
      expect(await tokens.authenticate(mine.secret), isNotNull);
      final stored = {for (final t in await tokenRepository.list()) t.id: t};
      expect(stored[theirs.token.id]!.isRevoked, isTrue);
    });

    test('refuses the last admin', () async {
      await expectLater(
        service.remove(owner.id, by: null),
        throwsA(
          isA<PersonConflictException>().having(
            (error) => error.message,
            'message',
            contains('Cannot remove Owner'),
          ),
        ),
      );
      expect((await service.get(owner.id)).isRemoved, isFalse);
    });

    test('removes an admin while another is left', () async {
      await service.create(name: 'Sam', role: PersonRole.admin, by: null);

      expect((await service.remove(owner.id, by: null)).isRemoved, isTrue);
    });

    test('refuses a person removed already', () async {
      final sam = await service.create(
        name: 'Sam',
        role: PersonRole.viewer,
        by: null,
      );
      await service.remove(sam.id, by: null);

      await expectLater(
        service.remove(sam.id, by: null),
        throwsA(isA<PersonNotFoundException>()),
      );
    });

    test('goes on with the next change after one fails', () async {
      await expectLater(
        service.remove('per_nobody', by: null),
        throwsA(isA<PersonNotFoundException>()),
      );

      expect(
        (await service.create(
          name: 'Sam',
          role: PersonRole.viewer,
          by: null,
        )).name,
        'Sam',
      );
    });
  });

  test('exceptions say what they are', () {
    expect(
      '${const PersonNotFoundException('per_1')}',
      'PersonNotFoundException: There is no person per_1.',
    );
    expect(
      '${const PersonConflictException('no')}',
      'PersonConflictException: no',
    );
    expect(
      '${const PersonRequestException('no')}',
      'PersonRequestException: no',
    );
    expect('${const PersonException('no')}', 'PersonException: no');
    expect(
      '${const PersonForbiddenException('no')}',
      'PersonForbiddenException: no',
    );
  });
}

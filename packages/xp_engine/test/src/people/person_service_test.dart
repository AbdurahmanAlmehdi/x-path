import 'dart:math';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

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
      );

      expect(sam.id, matches(RegExp(r'^per_[0-9a-f]{16}$')));
      expect(sam.name, 'Sam');
      expect(sam.role, PersonRole.releaser);
      expect(sam.createdAt, DateTime.utc(2026, 11, 13, 9));
      expect(sam.isRemoved, isFalse);
      expect(await service.get(sam.id), sam);
      expect(await service.list(), [owner, sam]);
    });

    test('refuses a blank or too long name', () async {
      for (final name in ['  ', 'x' * (maxPersonNameLength + 1)]) {
        await expectLater(
          service.create(name: name, role: PersonRole.viewer),
          throwsA(isA<PersonRequestException>()),
        );
      }
      expect(await service.list(), [owner]);
    });

    test('refuses the name of an active person, ignoring case', () async {
      await expectLater(
        service.create(name: 'OWNER', role: PersonRole.viewer),
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
      final sam = await service.create(name: 'Sam', role: PersonRole.viewer);
      await service.remove(sam.id);

      final again = await service.create(name: 'Sam', role: PersonRole.viewer);

      expect(again.id, isNot(sam.id));
    });
  });

  group('get', () {
    test('finds a removed person too', () async {
      final sam = await service.create(name: 'Sam', role: PersonRole.viewer);
      await service.remove(sam.id);

      expect((await service.get(sam.id)).isRemoved, isTrue);
    });

    test('throws for an unknown id', () {
      expect(
        service.get('per_nobody'),
        throwsA(isA<PersonNotFoundException>()),
      );
    });
  });

  group('rename', () {
    test('renames an active person', () async {
      final renamed = await service.rename(owner.id, ' Abdu ');

      expect(renamed, owner.copyWith(name: 'Abdu'));
      expect(await service.get(owner.id), renamed);
    });

    test('lets a person keep their name in another case', () async {
      expect((await service.rename(owner.id, 'OWNER')).name, 'OWNER');
    });

    test("refuses another active person's name", () async {
      await service.create(name: 'Sam', role: PersonRole.viewer);

      await expectLater(
        service.rename(owner.id, 'sam'),
        throwsA(isA<PersonConflictException>()),
      );
    });

    test('refuses an unknown or removed person', () async {
      final sam = await service.create(name: 'Sam', role: PersonRole.viewer);
      await service.remove(sam.id);

      for (final id in ['per_nobody', sam.id]) {
        await expectLater(
          service.rename(id, 'New'),
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

  group('setRole', () {
    test('changes the role, which applies to the next request', () async {
      final sam = await service.create(name: 'Sam', role: PersonRole.admin);
      final issued = await tokens.issue(
        name: 'xp',
        kind: DeviceTokenKind.cli,
        personId: sam.id,
      );

      final changed = await service.setRole(sam.id, PersonRole.viewer);

      expect(changed.role, PersonRole.viewer);
      expect(
        (await tokens.authenticate(issued.secret))?.role,
        PersonRole.viewer,
      );
    });

    test('refuses to demote the last admin', () async {
      await service.create(name: 'Sam', role: PersonRole.releaser);

      await expectLater(
        service.setRole(owner.id, PersonRole.releaser),
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
      expect(await service.setRole(owner.id, PersonRole.admin), owner);
    });

    test('demotes an admin while another is left', () async {
      await service.create(name: 'Sam', role: PersonRole.admin);

      expect(
        (await service.setRole(owner.id, PersonRole.developer)).role,
        PersonRole.developer,
      );
    });

    test(
      'lets only one of two concurrent demotions of two admins pass',
      () async {
        final sam = await service.create(name: 'Sam', role: PersonRole.admin);

        final results = await Future.wait([
          for (final id in [owner.id, sam.id])
            service
                .setRole(id, PersonRole.viewer)
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
      final sam = await service.create(name: 'Sam', role: PersonRole.developer);
      final theirs = await tokens.issue(
        name: 'xp',
        kind: DeviceTokenKind.cli,
        personId: sam.id,
      );
      final mine = await tokens.issue(name: 'app', kind: DeviceTokenKind.app);
      clock.advance(const Duration(minutes: 1));

      final removed = await service.remove(sam.id);

      expect(removed.removedAt, DateTime.utc(2026, 11, 13, 9, 1));
      expect(await service.get(sam.id), removed);
      expect(await tokens.authenticate(theirs.secret), isNull);
      expect(await tokens.authenticate(mine.secret), isNotNull);
      final stored = {for (final t in await tokenRepository.list()) t.id: t};
      expect(stored[theirs.token.id]!.isRevoked, isTrue);
    });

    test('refuses the last admin', () async {
      await expectLater(
        service.remove(owner.id),
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
      await service.create(name: 'Sam', role: PersonRole.admin);

      expect((await service.remove(owner.id)).isRemoved, isTrue);
    });

    test('refuses a person removed already', () async {
      final sam = await service.create(name: 'Sam', role: PersonRole.viewer);
      await service.remove(sam.id);

      await expectLater(
        service.remove(sam.id),
        throwsA(isA<PersonNotFoundException>()),
      );
    });

    test('goes on with the next change after one fails', () async {
      await expectLater(
        service.remove('per_nobody'),
        throwsA(isA<PersonNotFoundException>()),
      );

      expect(
        (await service.create(name: 'Sam', role: PersonRole.viewer)).name,
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
  });
}

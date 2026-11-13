import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';

void main() {
  group('PersonRole', () {
    test('orders viewer < developer < releaser < admin', () {
      expect(PersonRole.values, [
        PersonRole.viewer,
        PersonRole.developer,
        PersonRole.releaser,
        PersonRole.admin,
      ]);
    });

    test('isAtLeast includes the role itself and every lower one', () {
      expect(PersonRole.releaser.isAtLeast(PersonRole.developer), isTrue);
      expect(PersonRole.releaser.isAtLeast(PersonRole.releaser), isTrue);
      expect(PersonRole.releaser.isAtLeast(PersonRole.admin), isFalse);
      expect(PersonRole.viewer.isAtLeast(PersonRole.developer), isFalse);
    });
  });

  group('Person', () {
    final sam = Person(
      id: 'per_1',
      name: 'Sam',
      role: PersonRole.releaser,
      createdAt: DateTime.utc(2026, 11, 13),
    );

    test('round-trips through JSON and leaves out removedAt while active', () {
      expect(sam.toJson(), {
        'id': 'per_1',
        'name': 'Sam',
        'role': 'releaser',
        'createdAt': '2026-11-13T00:00:00.000Z',
      });
      expect(Person.fromJson(sam.toJson()), sam);
      expect(sam.isRemoved, isFalse);
    });

    test('carries removedAt once removed', () {
      final removed = sam.copyWith(removedAt: DateTime.utc(2026, 11, 14));

      expect(removed.isRemoved, isTrue);
      expect(removed.toJson()['removedAt'], '2026-11-14T00:00:00.000Z');
      expect(Person.fromJson(removed.toJson()), removed);
    });

    test('copyWith changes only what it is given', () {
      expect(sam.copyWith(), sam);
      expect(
        sam.copyWith(name: 'Sam K', role: PersonRole.admin),
        Person(
          id: 'per_1',
          name: 'Sam K',
          role: PersonRole.admin,
          createdAt: DateTime.utc(2026, 11, 13),
        ),
      );
    });
  });
}

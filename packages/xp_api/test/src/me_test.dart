import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';

void main() {
  group('Permission', () {
    test('uses snake_case on the wire and names its lowest role', () {
      expect(
        [for (final p in Permission.values) p.wire],
        ['develop', 'decide_approval', 'release', 'administer'],
      );
      expect(
        [for (final p in Permission.values) p.minimumRole],
        [
          PersonRole.developer,
          PersonRole.releaser,
          PersonRole.releaser,
          PersonRole.admin,
        ],
      );
    });
  });

  group('Me', () {
    final me = Me(
      person: Person(
        id: 'per_1',
        name: 'Sam',
        role: PersonRole.developer,
        createdAt: DateTime.utc(2026, 11, 13),
      ),
      token: TokenInfo(
        id: 'tok_1',
        name: 'laptop',
        kind: DeviceTokenKind.cli,
        createdAt: DateTime.utc(2026, 11, 13),
        personId: 'per_1',
      ),
      permissions: const [Permission.develop],
    );

    test('round-trips through JSON', () {
      expect(me.toJson()['permissions'], ['develop']);
      expect(Me.fromJson(me.toJson()), me);
    });

    test('says what it may do', () {
      expect(me.may(Permission.develop), isTrue);
      expect(me.may(Permission.decideApproval), isFalse);
    });
  });
}

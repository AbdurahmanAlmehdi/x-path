import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/people.dart';

void main() {
  DeviceToken token(DeviceTokenKind kind) => DeviceToken(
    id: 'tok_1',
    name: 'n',
    kind: kind,
    hash: 'h',
    createdAt: DateTime.utc(2026),
    personId: kind == DeviceTokenKind.runner ? null : owner.id,
  );

  group('runOrigin', () {
    test('is the person for the tokens people use', () {
      for (final kind in [
        DeviceTokenKind.app,
        DeviceTokenKind.cli,
        DeviceTokenKind.web,
      ]) {
        expect(
          token(kind).withPerson(owner).runOrigin,
          RunOrigin(
            kind: RunOriginKind.person,
            tokenId: 'tok_1',
            personId: owner.id,
            personName: owner.name,
          ),
        );
      }
    });

    test('is an agent acting for its person for an mcp token', () {
      expect(
        token(DeviceTokenKind.mcp).withPerson(owner).runOrigin,
        RunOrigin(
          kind: RunOriginKind.agent,
          tokenId: 'tok_1',
          personId: owner.id,
          personName: owner.name,
        ),
      );
    });

    test('is null without a person read', () {
      expect(token(DeviceTokenKind.runner).runOrigin, isNull);
      expect(token(DeviceTokenKind.cli).runOrigin, isNull);
    });
  });
}

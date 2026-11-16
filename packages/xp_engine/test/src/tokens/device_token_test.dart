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

  group('expiry', () {
    final at = DateTime.utc(2026, 11, 14, 9);

    test('a token without an expiry never expires', () {
      final valid = token(DeviceTokenKind.app);

      expect(valid.isExpiredAt(at.add(const Duration(days: 999))), isFalse);
      expect(valid.isValidAt(at), isTrue);
      expect(valid.revoked(at).isValidAt(at), isFalse);
    });

    test('a token expires at its expiry, and keeps it when copied', () {
      final web = DeviceToken(
        id: 'tok_1',
        name: 'Browser',
        kind: DeviceTokenKind.web,
        hash: 'h',
        createdAt: at,
        expiresAt: at.add(const Duration(hours: 8)),
        personId: owner.id,
      );

      expect(web.isValidAt(at.add(const Duration(hours: 7))), isTrue);
      expect(web.isExpiredAt(at.add(const Duration(hours: 8))), isTrue);
      expect(web.isValidAt(at.add(const Duration(hours: 8))), isFalse);
      expect(web.withPerson(owner).expiresAt, web.expiresAt);
      expect(web.revoked(at).expiresAt, web.expiresAt);
    });

    test('a renewed token expires later, and keeps the rest', () {
      final later = at.add(const Duration(days: 90));
      final cli = token(DeviceTokenKind.cli).revoked(at).withPerson(owner);

      final renewed = cli.renewed(later);

      expect(renewed.expiresAt, later);
      expect(renewed.revokedAt, at);
      expect(renewed.person, owner);
      expect(renewed.hash, cli.hash);
    });
  });
}

import 'dart:convert';

import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  const key = AscKey(
    keyId: 'ABC123DEF4',
    issuerId: '57246542-96fe-1a63-e053-0824d011072a',
    privateKey:
        '-----BEGIN PRIVATE KEY-----\nsecret\n-----END PRIVATE KEY-----\n',
  );

  group('the stored form', () {
    test('round trips', () {
      expect(AscKey.fromSecret(key.toSecret()), key);
    });

    test('keeps the kind', () {
      const individual = AscKey(
        keyId: 'K',
        issuerId: 'I',
        privateKey: 'p',
        kind: AscKeyKind.individual,
      );

      expect(AscKey.fromSecret(individual.toSecret()), individual);
      expect(
        AscKey.fromSecret(individual.toSecret()).kind,
        AscKeyKind.individual,
      );
    });

    test('defaults to a team key', () {
      final read = AscKey.fromSecret(
        jsonEncode({'keyId': 'K', 'issuerId': 'I', 'privateKey': 'p'}),
      );

      expect(read.kind, AscKeyKind.team);
    });

    for (final (json, message) in [
      ('not json', 'not JSON'),
      ('[]', 'must be a JSON object'),
      ('{"issuerId":"I","privateKey":"p"}', 'needs "keyId"'),
      ('{"keyId":"K","privateKey":"p"}', 'needs "issuerId"'),
      ('{"keyId":"K","issuerId":"I","privateKey":" "}', 'needs "privateKey"'),
      (
        '{"keyId":"K","issuerId":"I","privateKey":"p","keyKind":"x"}',
        'keyKind',
      ),
      ('{"keyId":"K","issuerId":"I","privateKey":"p","keyKind":1}', 'keyKind'),
    ]) {
      test('rejects $json', () {
        expect(
          () => AscKey.fromSecret(json),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains(message),
            ),
          ),
        );
      });
    }
  });

  group('altool file names', () {
    test('AuthKey_ for a team key and ApiKey_ for an individual key', () {
      expect(key.fileName, 'AuthKey_ABC123DEF4.p8');
      expect(AscKeyKind.individual.keyFileName('K1'), 'ApiKey_K1.p8');
    });
  });

  test('never prints the private key', () {
    expect('$key', 'AscKey(ABC123DEF4, team)');
    expect('$key', isNot(contains('secret')));
  });

  test('fromWire finds a kind or none', () {
    expect(AscKeyKind.fromWire('individual'), AscKeyKind.individual);
    expect(AscKeyKind.fromWire('other'), isNull);
  });
}

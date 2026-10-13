import 'dart:convert';

import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xp_fake_asc/xp_fake_asc.dart';

final _start = DateTime.utc(2026, 10, 13, 12);

const _team = AscKey(
  keyId: fakeAscKeyId,
  issuerId: fakeAscIssuerId,
  privateKey: fakeAscPrivateKeyPem,
);

const _individual = AscKey(
  keyId: 'INDIVKEY01',
  issuerId: fakeAscIssuerId,
  privateKey: fakeAscPrivateKeyPem,
  kind: AscKeyKind.individual,
);

Map<String, dynamic> _part(String token, int index) => jsonDecode(
  utf8.decode(base64Url.decode(base64Url.normalize(token.split('.')[index]))),
) as Map<String, dynamic>;

void main() {
  late ManualClock clock;

  setUp(() => clock = ManualClock(_start));

  AscTokenVerifier verifierFor(AscKey key) => AscTokenVerifier(
    keys: [
      FakeAscKey(
        keyId: key.keyId,
        publicKeyPem: fakeAscPublicKeyPem,
        kind: key.kind == AscKeyKind.team
            ? FakeAscKeyKind.team
            : FakeAscKeyKind.individual,
      ),
    ],
    now: clock.now,
  );

  group('a team key token', () {
    late String token;

    setUp(() => token = AscTokenProvider(key: _team, clock: clock).token());

    test('has the header and the claims Apple documents', () {
      expect(_part(token, 0), {
        'alg': 'ES256',
        'kid': fakeAscKeyId,
        'typ': 'JWT',
      });
      final seconds = _start.millisecondsSinceEpoch ~/ 1000;
      expect(_part(token, 1), {
        'iss': fakeAscIssuerId,
        'iat': seconds,
        'exp': seconds + 900,
        'aud': 'appstoreconnect-v1',
      });
    });

    test('lives less than 20 minutes', () {
      final claims = _part(token, 1);

      expect((claims['exp'] as int) - (claims['iat'] as int), lessThan(1200));
    });

    test('is accepted by a verifier that checks the signature and claims', () {
      expect(verifierFor(_team).problem(token), isNull);
    });
  });

  group('an individual key token', () {
    test('says sub: user and has no issuer', () {
      final token = AscTokenProvider(key: _individual, clock: clock).token();

      final claims = _part(token, 1);
      expect(claims['sub'], 'user');
      expect(claims.containsKey('iss'), isFalse);
      expect(verifierFor(_individual).problem(token), isNull);
    });
  });

  group('the cache', () {
    late AscTokenProvider provider;

    setUp(() => provider = AscTokenProvider(key: _team, clock: clock));

    test('keeps a token until it is near its end', () {
      final first = provider.token();

      clock.advance(const Duration(minutes: 12, seconds: 59));
      expect(provider.token(), first);

      clock.advance(const Duration(seconds: 2));
      final second = provider.token();
      expect(second, isNot(first));
      expect(
        _part(second, 1)['iat'],
        clock.now().millisecondsSinceEpoch ~/ 1000,
      );
    });

    test('never hands out an expired token', () {
      final first = provider.token();

      clock.advance(const Duration(hours: 3));

      expect(verifierFor(_team).problem(first), 'The token has expired.');
      expect(verifierFor(_team).problem(provider.token()), isNull);
    });

    test('signs the same moment to the same token', () {
      final other = AscTokenProvider(key: _team, clock: ManualClock(_start));

      expect(other.token(), provider.token());
    });
  });

  test('a key that is not a .p8 is a FormatException', () {
    final provider = AscTokenProvider(
      key: const AscKey(keyId: 'K', issuerId: 'I', privateKey: 'nope'),
      clock: clock,
    );

    expect(provider.token, throwsA(isA<FormatException>()));
  });
}

import 'package:test/test.dart';
import 'package:xp_fake_asc/xp_fake_asc.dart';

import 'helpers/mint.dart';

/// Signed with `openssl dgst -sha256 -sign` (DER, converted to r || s) over the
/// header `{"alg":"ES256","kid":"TESTKEY001","typ":"JWT"}` and the claims
/// `{"iss":"69a6de70-1111-47e3-e053-5b8c7c11a4d1","iat":1792000000,
/// "exp":1792000900,"aud":"appstoreconnect-v1"}`.
const _opensslToken =
    'eyJhbGciOiJFUzI1NiIsImtpZCI6IlRFU1RLRVkwMDEiLCJ0eXAiOiJKV1QifQ.'
    'eyJpc3MiOiI2OWE2ZGU3MC0xMTExLTQ3ZTMtZTA1My01YjhjN2MxMWE0ZDEiLCJpYXQiOjE3'
    'OTIwMDAwMDAsImV4cCI6MTc5MjAwMDkwMCwiYXVkIjoiYXBwc3RvcmVjb25uZWN0LXYxIn0.'
    'Om8a0PrCkIJ1VBWE3bMo1ZdMxgyeMJER9MbBXXk36_adMCuJ41qkNeiCy6z8_50ijOP0U8ff'
    'K1aiYkZGKcA0hA';

const _individual = FakeAscKey(
  keyId: 'INDIVKEY01',
  publicKeyPem: fakeAscPublicKeyPem,
  kind: FakeAscKeyKind.individual,
);

void main() {
  late DateTime now;
  late AscTokenVerifier verifier;

  setUp(() {
    now = testNow;
    verifier = AscTokenVerifier(
      keys: [fakeAscTestKey, _individual],
      now: () => now,
    );
  });

  group('a token signed by OpenSSL', () {
    test('is valid while it lives', () {
      now = DateTime.fromMillisecondsSinceEpoch(1792000060 * 1000, isUtc: true);

      expect(verifier.problem(_opensslToken), isNull);
    });

    test('has expired after its exp', () {
      now = DateTime.fromMillisecondsSinceEpoch(1792000901 * 1000, isUtc: true);

      expect(verifier.problem(_opensslToken), 'The token has expired.');
    });
  });

  group('a token minted by the test helper', () {
    test('is valid', () {
      expect(verifier.problem(mint()), isNull);
    });

    test('of an individual key needs sub user and no iss', () {
      final header = {'kid': 'INDIVKEY01'};

      expect(
        verifier.problem(
          mint(header: header, claims: {'iss': null, 'sub': 'user'}),
        ),
        isNull,
      );
      expect(
        verifier.problem(mint(header: header)),
        contains('individual key token needs sub = user'),
      );
      expect(
        verifier.problem(mint(header: header, claims: {'sub': 'user'})),
        contains('individual key token needs sub = user'),
      );
    });
  });

  group('a token is refused', () {
    test('when there is none', () {
      expect(verifier.problem(null), 'There is no bearer token.');
    });

    test('when it is not a JWT', () {
      expect(verifier.problem('abc'), 'The token is not a JWT.');
    });

    test('when it is not base64url JSON', () {
      expect(verifier.problem('a.b.c'), 'The token is not base64url JSON.');
    });

    test('with another algorithm', () {
      expect(
        verifier.problem(mint(header: {'alg': 'RS256'})),
        'The token must use alg ES256.',
      );
    });

    test('from an unknown key', () {
      expect(
        verifier.problem(mint(header: {'kid': 'NOPE'})),
        'The key id NOPE is unknown.',
      );
    });

    test('with a DER signature', () {
      expect(
        verifier.problem(derSigned(mint())),
        'The signature must be 64 bytes (r || s), not DER.',
      );
    });

    test('with a signature that does not match', () {
      expect(
        verifier.problem(mint(tamper: true)),
        'The signature does not match the key.',
      );
    });

    test('for another audience', () {
      expect(
        verifier.problem(mint(claims: {'aud': 'appstoreconnect-v2'})),
        'The audience must be appstoreconnect-v1.',
      );
    });

    test('without iat or exp', () {
      expect(
        verifier.problem(mint(claims: {'exp': null})),
        'The token needs iat and exp.',
      );
    });

    test('when it has expired', () {
      final seconds = testNow.millisecondsSinceEpoch ~/ 1000;

      expect(
        verifier.problem(mint(claims: {'exp': seconds - 1})),
        'The token has expired.',
      );
    });

    test('when it lives longer than 20 minutes', () {
      final seconds = testNow.millisecondsSinceEpoch ~/ 1000;

      expect(
        verifier.problem(
          mint(claims: {'iat': seconds - 600, 'exp': seconds + 1201 - 600}),
        ),
        'The token lives longer than 20 minutes.',
      );
    });

    test('when it expires more than 20 minutes from now', () {
      final seconds = testNow.millisecondsSinceEpoch ~/ 1000;

      expect(
        verifier.problem(
          mint(claims: {'iat': seconds + 1000, 'exp': seconds + 1300}),
        ),
        'The token expires more than 20 minutes from now.',
      );
    });

    test('of a team key with the wrong issuer or a sub', () {
      expect(
        verifier.problem(mint(claims: {'iss': 'someone-else'})),
        contains('team key token needs iss'),
      );
      expect(
        verifier.problem(mint(claims: {'sub': 'user'})),
        contains('team key token needs iss'),
      );
    });
  });
}

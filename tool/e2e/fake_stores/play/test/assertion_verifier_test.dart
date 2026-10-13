import 'dart:convert';

import 'package:test/test.dart';
import 'package:xp_fake_play/xp_fake_play.dart';

import 'helpers/mint.dart';

void main() {
  final audience = Uri.parse('http://localhost:1234/token');
  final verifier = AssertionVerifier(
    accounts: const [fakePlayTestAccount],
    audience: '$audience',
    now: () => testNow,
  );

  String? problem(String? assertion) =>
      verifier.problem(assertion)?.description;

  test('accepts a valid assertion', () {
    expect(verifier.problem(mint(audience)), isNull);
  });

  test('says what is wrong with one that is not', () {
    final cases = <(String, String)>[
      ('Invalid JWT Signature.', mint(audience, tamper: true)),
      (
        'Invalid JWT Signature.',
        mint(audience, privateKeyPem: fakePlayOtherPrivateKeyPem),
      ),
      (
        'the issuer nobody@x is unknown',
        mint(audience, claims: {'iss': 'nobody@x'}),
      ),
      ('the algorithm must be RS256', mint(audience, header: {'alg': 'HS256'})),
      ('The scope must be', mint(audience, claims: {'scope': 'email'})),
      ('the audience must be', mint(audience, claims: {'aud': 'other'})),
      ('iat and exp are needed', mint(audience, claims: {'iat': null})),
      ('has expired', mint(audience, claims: {'exp': _seconds - 1})),
      (
        'short-lived token (60 minutes)',
        mint(audience, claims: {'exp': _seconds + 7200}),
      ),
      (
        'used too early',
        mint(
          audience,
          claims: {'iat': _seconds + 4000, 'exp': _seconds + 5000},
        ),
      ),
    ];
    for (final (reason, assertion) in cases) {
      expect(problem(assertion), contains(reason), reason: reason);
    }
  });

  test('rejects what is not a JWT', () {
    expect(verifier.problem(null)!.error, 'invalid_request');
    expect(problem('a.b'), contains('Not a JWT'));
    expect(problem('!!.!!.!!'), contains('base64url JSON'));
    expect(
      problem('${base64Url.encode(utf8.encode('[]'))}.e30.AAAA'),
      contains('base64url JSON'),
    );
  });

  test('a signature of the wrong length does not verify', () {
    final parts = mint(audience).split('.');

    expect(problem('${parts[0]}.${parts[1]}.AAAA'), 'Invalid JWT Signature.');
  });
}

int get _seconds => testNow.millisecondsSinceEpoch ~/ 1000;

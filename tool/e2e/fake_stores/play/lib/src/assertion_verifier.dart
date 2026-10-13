import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';
import 'package:xp_fake_play/src/fake_play_account.dart';

/// The OAuth2 scope of the Google Play Developer API.
const fakePlayScope = 'https://www.googleapis.com/auth/androidpublisher';

/// What is wrong with an assertion, in the words of Google's token endpoint.
class AssertionProblem {
  /// Creates a problem.
  const new(this.error, this.description);

  /// The OAuth2 `error`, such as `invalid_grant`.
  final String error;

  /// The `error_description`.
  final String description;
}

/// Checks the signed assertions of the JWT bearer flow the way Google's token
/// endpoint does.
///
/// An assertion is valid when it is RS256 signed by a known service account,
/// names it in `iss`, asks for [fakePlayScope] in `scope`, has the token
/// endpoint as `aud`, has not expired, and lives at most an hour.
class AssertionVerifier {
  /// Creates a verifier of assertions signed by [accounts] for the token
  /// endpoint [audience]. `now` is the clock the expiry is checked against.
  new({
    required Iterable<FakePlayAccount> accounts,
    required this.audience,
    required this._now,
  }) : _accounts = {
         for (final account in accounts) account.clientEmail: account,
       };

  /// The longest an assertion may live: one hour.
  static const maxLifetime = Duration(hours: 1);

  /// The address of the token endpoint: the `aud` of valid assertions.
  final String audience;

  final Map<String, FakePlayAccount> _accounts;
  final DateTime Function() _now;

  /// Why [assertion] is not valid, or `null` if it is.
  AssertionProblem? problem(String? assertion) {
    if (assertion == null) {
      return const AssertionProblem('invalid_request', 'Missing assertion.');
    }
    final parts = assertion.split('.');
    const bad = AssertionProblem('invalid_grant', 'Invalid JWT: Not a JWT.');
    if (parts.length != 3) return bad;
    final Map<String, dynamic> header;
    final Map<String, dynamic> claims;
    final Uint8List signature;
    try {
      header = _json(parts[0]);
      claims = _json(parts[1]);
      signature = Uint8List.fromList(
        base64Url.decode(base64Url.normalize(parts[2])),
      );
    } on Object {
      return const AssertionProblem(
        'invalid_grant',
        'Invalid JWT: Not base64url JSON.',
      );
    }
    if (header['alg'] != 'RS256') {
      return const AssertionProblem(
        'invalid_grant',
        'Invalid JWT: the algorithm must be RS256.',
      );
    }
    final account = _accounts[claims['iss']];
    if (account == null) {
      return AssertionProblem(
        'invalid_grant',
        'Invalid JWT: the issuer ${claims['iss']} is unknown.',
      );
    }
    if (!_verifies(
      account,
      utf8.encode('${parts[0]}.${parts[1]}'),
      signature,
    )) {
      return const AssertionProblem('invalid_grant', 'Invalid JWT Signature.');
    }
    if (claims['scope'] != fakePlayScope) {
      return const AssertionProblem(
        'invalid_scope',
        'The scope must be $fakePlayScope.',
      );
    }
    if (claims['aud'] != audience) {
      return AssertionProblem(
        'invalid_grant',
        'Invalid JWT: the audience must be $audience.',
      );
    }
    final iat = claims['iat'];
    final exp = claims['exp'];
    if (exp is! int || iat is! int) {
      return const AssertionProblem(
        'invalid_grant',
        'Invalid JWT: iat and exp are needed.',
      );
    }
    final now = _now().millisecondsSinceEpoch ~/ 1000;
    if (exp <= now) {
      return const AssertionProblem(
        'invalid_grant',
        'Invalid JWT: Token must be a short-lived token and in a '
            'reasonable timeframe. The token has expired.',
      );
    }
    if (exp - iat > maxLifetime.inSeconds) {
      return const AssertionProblem(
        'invalid_grant',
        'Invalid JWT: Token must be a short-lived token (60 minutes).',
      );
    }
    if (iat > now + 300) {
      return const AssertionProblem(
        'invalid_grant',
        'Invalid JWT: Token used too early; check the clock.',
      );
    }
    return null;
  }

  Map<String, dynamic> _json(String part) =>
      jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(part))))
          as Map<String, dynamic>;

  bool _verifies(
    FakePlayAccount account,
    List<int> message,
    Uint8List signature,
  ) {
    final verifier = RSASigner(SHA256Digest(), '0609608648016503040201')
      ..init(false, PublicKeyParameter<RSAPublicKey>(_publicKey(account)));
    return verifier.verifySignature(
      Uint8List.fromList(message),
      RSASignature(signature),
    );
  }

  /// The key of a `BEGIN PUBLIC KEY` block (SubjectPublicKeyInfo).
  RSAPublicKey _publicKey(FakePlayAccount account) {
    final body = account.publicKeyPem
        .split('\n')
        .where((line) => !line.startsWith('-----') && line.trim().isNotEmpty)
        .join();
    final info = ASN1Parser(base64.decode(body)).nextObject() as ASN1Sequence;
    final bits = info.elements![1] as ASN1BitString;
    // The first byte of a bit string counts its unused bits.
    final key =
        ASN1Parser(Uint8List.fromList(bits.valueBytes!.sublist(1))).nextObject()
            as ASN1Sequence;
    return RSAPublicKey(
      (key.elements![0] as ASN1Integer).integer!,
      (key.elements![1] as ASN1Integer).integer!,
    );
  }
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';
import 'package:xp_fake_asc/src/fake_asc_key.dart';

/// Checks App Store Connect tokens the way Apple does, and says what is wrong
/// with one that fails.
///
/// A token is valid when it is ES256 signed (raw `r || s`, 64 bytes) by a
/// known key, names that key in `kid`, has `aud: appstoreconnect-v1`, has not
/// expired, lives at most 20 minutes, and identifies the issuer as its kind of
/// key does: `iss` for a team key, `sub: user` and no `iss` for an individual
/// key.
class AscTokenVerifier {
  /// Creates a verifier of tokens signed by [keys]. `now` is the clock the
  /// expiry is checked against.
  new({required Iterable<FakeAscKey> keys, required this._now})
    : _keys = {for (final key in keys) key.keyId: key};

  /// The longest a token may live: 20 minutes.
  static const maxLifetime = Duration(minutes: 20);

  final Map<String, FakeAscKey> _keys;
  final DateTime Function() _now;

  /// Why [token] is not valid, or `null` if it is.
  String? problem(String? token) {
    if (token == null) return 'There is no bearer token.';
    final parts = token.split('.');
    if (parts.length != 3) return 'The token is not a JWT.';
    final Map<String, dynamic> header;
    final Map<String, dynamic> claims;
    final Uint8List signature;
    try {
      header = _json(parts[0]);
      claims = _json(parts[1]);
      signature = Uint8List.fromList(
        base64Url.decode(base64Url.normalize(parts[2])),
      );
    } on FormatException {
      return 'The token is not base64url JSON.';
    }
    if (header['alg'] != 'ES256') return 'The token must use alg ES256.';
    final key = _keys[header['kid']];
    if (key == null) return 'The key id ${header['kid']} is unknown.';
    if (signature.length != 64) {
      return 'The signature must be 64 bytes (r || s), not DER.';
    }
    if (!_verifies(key, utf8.encode('${parts[0]}.${parts[1]}'), signature)) {
      return 'The signature does not match the key.';
    }
    if (claims['aud'] != 'appstoreconnect-v1') {
      return 'The audience must be appstoreconnect-v1.';
    }
    final iat = claims['iat'];
    final exp = claims['exp'];
    if (exp is! int || iat is! int) return 'The token needs iat and exp.';
    final now = _now().millisecondsSinceEpoch ~/ 1000;
    if (exp <= now) return 'The token has expired.';
    if (exp - iat > maxLifetime.inSeconds) {
      return 'The token lives longer than 20 minutes.';
    }
    if (exp - now > maxLifetime.inSeconds) {
      return 'The token expires more than 20 minutes from now.';
    }
    return switch (key.kind) {
      FakeAscKeyKind.team =>
        claims['iss'] != key.issuerId || claims.containsKey('sub')
            ? 'A team key token needs iss = the issuer id and no sub.'
            : null,
      FakeAscKeyKind.individual =>
        claims['sub'] != 'user' || claims.containsKey('iss')
            ? 'An individual key token needs sub = user and no iss.'
            : null,
    };
  }

  Map<String, dynamic> _json(String part) =>
      jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(part))))
          as Map<String, dynamic>;

  bool _verifies(FakeAscKey key, List<int> message, Uint8List signature) {
    final params = ECDomainParameters('prime256v1');
    final verifier = ECDSASigner(SHA256Digest())
      ..init(false, PublicKeyParameter<ECPublicKey>(_publicKey(key, params)));
    return verifier.verifySignature(
      Uint8List.fromList(message),
      ECSignature(
        _integer(signature.sublist(0, 32)),
        _integer(signature.sublist(32)),
      ),
    );
  }

  /// The point of a `BEGIN PUBLIC KEY` block (SubjectPublicKeyInfo).
  ECPublicKey _publicKey(FakeAscKey key, ECDomainParameters params) {
    final body = key.publicKeyPem
        .split('\n')
        .where((line) => !line.startsWith('-----') && line.trim().isNotEmpty)
        .join();
    final info = ASN1Parser(base64.decode(body)).nextObject() as ASN1Sequence;
    final bits = info.elements![1] as ASN1BitString;
    // The first byte of a bit string counts its unused bits.
    final point = bits.valueBytes!.sublist(1);
    return ECPublicKey(params.curve.decodePoint(point), params);
  }

  BigInt _integer(List<int> bytes) => bytes.fold(
    BigInt.zero,
    (value, byte) => (value << 8) | BigInt.from(byte),
  );
}

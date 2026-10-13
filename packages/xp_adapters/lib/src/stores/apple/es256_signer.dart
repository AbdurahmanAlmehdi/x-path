import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';

/// `ecPublicKey` and `prime256v1`, the algorithm identifier of a P-256 key.
const _p256Algorithm = '1.2.840.10045.2.1 1.2.840.10045.3.1.7';

class _NotP256 implements Exception {
  const new();
}

/// Signs with ECDSA on P-256 and SHA-256 and writes the signature the way a
/// JWT (JWS, RFC 7518 section 3.4) wants it: the 32-byte `r` followed by the
/// 32-byte `s`, not DER.
///
/// The nonce is deterministic (RFC 6979), so a signature depends on the key and
/// the message alone.
class Es256Signer {
  /// Creates a signer for the private scalar [d].
  ///
  /// Throws a [FormatException] if [d] is not a valid P-256 private key.
  factory fromScalar(BigInt d) {
    final parameters = ECDomainParameters('prime256v1');
    if (d <= BigInt.zero || d >= parameters.n) {
      throw const FormatException('The private key is out of range.');
    }
    return Es256Signer._(ECPrivateKey(d, parameters));
  }

  /// Reads the `.p8` file App Store Connect gives out: an unencrypted PKCS#8
  /// private key on the prime256v1 curve in a `-----BEGIN PRIVATE KEY-----`
  /// block.
  ///
  /// Throws a [FormatException] for anything else. The message never contains
  /// the key.
  factory fromPem(String pem) {
    final body = pem
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('-----'))
        .join();
    final BigInt scalar;
    try {
      final info = ASN1Parser(base64.decode(body)).nextObject() as ASN1Sequence;
      final algorithm = info.elements![1] as ASN1Sequence;
      final oids = [
        for (final element in algorithm.elements!)
          (element as ASN1ObjectIdentifier).objectIdentifierAsString,
      ];
      if (oids.join(' ') != _p256Algorithm) throw const _NotP256();
      final key =
          ASN1Parser(info.elements![2].valueBytes).nextObject() as ASN1Sequence;
      scalar = key.elements![1].valueBytes!.fold(
        BigInt.zero,
        (value, byte) => value << 8 | BigInt.from(byte),
      );
    } on _NotP256 {
      throw const FormatException('The key is not a P-256 key.');
    } on Object {
      throw const FormatException(
        'The key is not an unencrypted PKCS#8 private key (a .p8 file).',
      );
    }
    return Es256Signer.fromScalar(scalar);
  }

  const new _(this._key);

  final ECPrivateKey _key;

  /// The signature of [message]: 64 bytes, `r || s`.
  Uint8List sign(List<int> message) {
    final signer = ECDSASigner(SHA256Digest(), HMac(SHA256Digest(), 64))
      ..init(true, PrivateKeyParameter<ECPrivateKey>(_key));
    final signature =
        signer.generateSignature(Uint8List.fromList(message)) as ECSignature;
    final raw = Uint8List(64);
    final mask = BigInt.from(0xff);
    for (var i = 0; i < 32; i++) {
      raw[31 - i] = ((signature.r >> (8 * i)) & mask).toInt();
      raw[63 - i] = ((signature.s >> (8 * i)) & mask).toInt();
    }
    return raw;
  }
}

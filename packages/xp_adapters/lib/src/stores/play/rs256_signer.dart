import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';

/// `rsaEncryption`, the algorithm identifier of an RSA key in PKCS#8.
const _rsaAlgorithm = '1.2.840.113549.1.1.1';

/// The DER prefix of the SHA-256 `DigestInfo` that PKCS#1 v1.5 signs.
const _sha256DigestInfo = '0609608648016503040201';

class _NotRsa implements Exception {
  const new();
}

/// Signs with RSASSA-PKCS1-v1_5 and SHA-256, the `RS256` of a JWT (RFC 7518
/// section 3.3). PKCS#1 v1.5 signatures are deterministic.
class Rs256Signer {
  /// Reads the `private_key` of a Google service account file: an
  /// unencrypted PKCS#8 RSA private key in a `-----BEGIN PRIVATE KEY-----`
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
    final RSAPrivateKey key;
    try {
      final info = ASN1Parser(base64.decode(body)).nextObject() as ASN1Sequence;
      final algorithm = info.elements![1] as ASN1Sequence;
      final oid = algorithm.elements![0] as ASN1ObjectIdentifier;
      if (oid.objectIdentifierAsString != _rsaAlgorithm) throw const _NotRsa();
      final rsa =
          ASN1Parser(info.elements![2].valueBytes).nextObject() as ASN1Sequence;
      BigInt at(int index) => (rsa.elements![index] as ASN1Integer).integer!;
      // Version, modulus, public exponent, private exponent, primes.
      key = RSAPrivateKey(at(1), at(3), at(4), at(5));
    } on _NotRsa {
      throw const FormatException('The key is not an RSA key.');
    } on Object {
      throw const FormatException(
        'The key is not an unencrypted PKCS#8 private key.',
      );
    }
    return Rs256Signer._(key);
  }

  const new _(this._key);

  final RSAPrivateKey _key;

  /// The signature of [message].
  Uint8List sign(List<int> message) {
    final signer = RSASigner(SHA256Digest(), _sha256DigestInfo)
      ..init(true, PrivateKeyParameter<RSAPrivateKey>(_key));
    return signer.generateSignature(Uint8List.fromList(message)).bytes;
  }
}

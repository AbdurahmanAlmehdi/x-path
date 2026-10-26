import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';
import 'package:xp_engine/xp_engine.dart';

/// [DistributionKeys] with pointycastle: an RSA key of [bits] bits (2048, as
/// Apple asks), PKCS#8, and a PKCS#10 request signed with SHA-256, which is
/// what Keychain Access makes on a Mac.
class RsaDistributionKeys implements DistributionKeys {
  /// Creates the generator; [bits] is smaller only in tests.
  const new({this.bits = 2048});

  /// The size of the keys.
  final int bits;

  /// The DER prefix of the SHA-256 `DigestInfo` that PKCS#1 v1.5 signs.
  static const _sha256DigestInfo = '0609608648016503040201';

  @override
  Future<DistributionKey> generate(String commonName) async {
    final seed = Random.secure();
    final random = FortunaRandom()
      ..seed(
        KeyParameter(
          Uint8List.fromList([for (var i = 0; i < 32; i++) seed.nextInt(256)]),
        ),
      );
    final pair =
        (RSAKeyGenerator()..init(
              ParametersWithRandom(
                RSAKeyGeneratorParameters(BigInt.from(65537), bits, 64),
                random,
              ),
            ))
            .generateKeyPair();
    final public = pair.publicKey;
    final private = pair.privateKey;
    ASN1Sequence rsaAlgorithm() => ASN1Sequence(
      elements: [
        ASN1ObjectIdentifier.fromIdentifierString('1.2.840.113549.1.1.1'),
        ASN1Null(),
      ],
    );
    final p = private.p!;
    final q = private.q!;
    final d = private.privateExponent!;
    final pkcs8 = ASN1Sequence(
      elements: [
        ASN1Integer(BigInt.zero),
        rsaAlgorithm(),
        ASN1OctetString(
          octets: ASN1Sequence(
            elements: [
              for (final value in [
                BigInt.zero,
                public.modulus!,
                public.exponent!,
                d,
                p,
                q,
                d % (p - BigInt.one),
                d % (q - BigInt.one),
                q.modInverse(p),
              ])
                ASN1Integer(value),
            ],
          ).encode(),
        ),
      ],
    );
    final info = ASN1Sequence(
      elements: [
        ASN1Integer(BigInt.zero),
        ASN1Sequence(
          elements: [
            ASN1Set(
              elements: [
                ASN1Sequence(
                  elements: [
                    ASN1ObjectIdentifier.fromIdentifierString('2.5.4.3'),
                    ASN1UTF8String(utf8StringValue: commonName),
                  ],
                ),
              ],
            ),
          ],
        ),
        ASN1Sequence(
          elements: [
            rsaAlgorithm(),
            ASN1BitString(
              stringValues: ASN1Sequence(
                elements: [
                  ASN1Integer(public.modulus),
                  ASN1Integer(public.exponent),
                ],
              ).encode(),
            ),
          ],
        ),
        // No attributes: [0] IMPLICIT SET OF, empty.
        ASN1Sequence(elements: [], tag: 0xa0),
      ],
    );
    final signer = RSASigner(SHA256Digest(), _sha256DigestInfo)
      ..init(true, PrivateKeyParameter<RSAPrivateKey>(private));
    final request = ASN1Sequence(
      elements: [
        info,
        ASN1Sequence(
          elements: [
            ASN1ObjectIdentifier.fromIdentifierString('1.2.840.113549.1.1.11'),
            ASN1Null(),
          ],
        ),
        ASN1BitString(
          stringValues: signer.generateSignature(info.encode()).bytes,
        ),
      ],
    );
    return (
      privateKeyPem: _pem('PRIVATE KEY', pkcs8.encode()),
      csrPem: _pem('CERTIFICATE REQUEST', request.encode()),
    );
  }

  static String _pem(String label, List<int> der) {
    final body = base64.encode(der);
    final lines = [
      for (var i = 0; i < body.length; i += 64)
        body.substring(i, min(i + 64, body.length)),
    ];
    return '-----BEGIN $label-----\n${lines.join('\n')}\n'
        '-----END $label-----\n';
  }
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';
import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';

/// The DER of a PEM block.
Uint8List _der(String pem) => base64.decode(
  pem
      .split('\n')
      .where((line) => line.isNotEmpty && !line.startsWith('-----'))
      .join(),
);

void main() {
  test('makes a PKCS#8 key and a PKCS#10 request signed with it', () async {
    final key = await const RsaDistributionKeys(bits: 1024)
        .generate('XPath Linux signing');

    expect(key.privateKeyPem, startsWith('-----BEGIN PRIVATE KEY-----\n'));
    expect(key.csrPem, startsWith('-----BEGIN CERTIFICATE REQUEST-----\n'));
    expect(key.csrPem, endsWith('-----END CERTIFICATE REQUEST-----\n'));
    // The key is one the RS256 signer (PKCS#8 RSA) reads.
    expect(() => Rs256Signer.fromPem(key.privateKeyPem), returnsNormally);

    final request = ASN1Parser(_der(key.csrPem)).nextObject() as ASN1Sequence;
    final info = request.elements![0] as ASN1Sequence;
    final subject = info.elements![1] as ASN1Sequence;
    final name =
        ((subject.elements!.single as ASN1Set).elements!.single as ASN1Sequence)
            .elements![1];
    expect(utf8.decode(name.valueBytes!), 'XPath Linux signing');
    final spki = info.elements![2] as ASN1Sequence;
    final bits = (spki.elements![1] as ASN1BitString).valueBytes!.sublist(1);
    final rsa = ASN1Parser(bits).nextObject() as ASN1Sequence;
    BigInt at(int i) => (rsa.elements![i] as ASN1Integer).integer!;
    expect(at(1), BigInt.from(65537));
    expect(at(0).bitLength, 1024);

    final signature = (request.elements![2] as ASN1BitString).valueBytes!
        .sublist(1);
    final verifier = RSASigner(SHA256Digest(), '0609608648016503040201')
      ..init(
        false,
        PublicKeyParameter<RSAPublicKey>(RSAPublicKey(at(0), at(1))),
      );
    expect(
      verifier.verifySignature(
        info.encodedBytes!,
        RSASignature(Uint8List.fromList(signature)),
      ),
      isTrue,
    );
  });

  test('makes a new key each time', () async {
    const keys = RsaDistributionKeys(bits: 512);

    final first = await keys.generate('a');
    final second = await keys.generate('a');

    expect(first.privateKeyPem, isNot(second.privateKeyPem));
  });
}

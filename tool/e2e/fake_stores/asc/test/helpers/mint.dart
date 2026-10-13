import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';
import 'package:xp_fake_asc/xp_fake_asc.dart';

/// The instant the tests stand at: 2026-10-13 12:00:00 UTC.
final testNow = DateTime.utc(2026, 10, 13, 12);

int get _seconds => testNow.millisecondsSinceEpoch ~/ 1000;

String _base64Url(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

/// A token for the fake server, signed by the test key. [claims] and [header]
/// replace the defaults field by field; a `null` value removes the field.
String mint({
  Map<String, Object?> claims = const {},
  Map<String, Object?> header = const {},
  String privateKeyPem = fakeAscPrivateKeyPem,
  bool tamper = false,
}) {
  final headerJson = <String, Object?>{
    'alg': 'ES256',
    'kid': fakeAscKeyId,
    'typ': 'JWT',
    ...header,
  }..removeWhere((_, value) => value == null);
  final claimsJson = <String, Object?>{
    'iss': fakeAscIssuerId,
    'iat': _seconds,
    'exp': _seconds + 900,
    'aud': 'appstoreconnect-v1',
    ...claims,
  }..removeWhere((_, value) => value == null);
  final signingInput =
      '${_base64Url(utf8.encode(jsonEncode(headerJson)))}.'
      '${_base64Url(utf8.encode(jsonEncode(claimsJson)))}';
  final signer = ECDSASigner(SHA256Digest(), HMac(SHA256Digest(), 64))
    ..init(true, PrivateKeyParameter<ECPrivateKey>(_privateKey(privateKeyPem)));
  final signature = signer.generateSignature(
    Uint8List.fromList(utf8.encode(signingInput)),
  ) as ECSignature;
  final raw = Uint8List(64);
  for (var i = 0; i < 32; i++) {
    raw[31 - i] = ((signature.r >> (8 * i)) & BigInt.from(0xff)).toInt();
    raw[63 - i] = ((signature.s >> (8 * i)) & BigInt.from(0xff)).toInt();
  }
  if (tamper) raw[0] ^= 1;
  return '$signingInput.${_base64Url(raw)}';
}

/// The signature of [token] as DER, which Apple does not accept.
String derSigned(String token) {
  final parts = token.split('.');
  final der = ASN1Sequence(
    elements: [ASN1Integer(BigInt.from(1)), ASN1Integer(BigInt.from(2))],
  ).encode();
  return '${parts[0]}.${parts[1]}.${_base64Url(der)}';
}

ECPrivateKey _privateKey(String pem) {
  final body = pem
      .split('\n')
      .where((line) => !line.startsWith('-----') && line.isNotEmpty)
      .join();
  final info = ASN1Parser(base64.decode(body)).nextObject() as ASN1Sequence;
  final inner =
      ASN1Parser(info.elements![2].valueBytes).nextObject() as ASN1Sequence;
  final scalar = inner.elements![1].valueBytes!;
  return ECPrivateKey(
    scalar.fold<BigInt>(BigInt.zero, (v, b) => (v << 8) | BigInt.from(b)),
    ECDomainParameters('prime256v1'),
  );
}

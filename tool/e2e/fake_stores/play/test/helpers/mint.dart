import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';
import 'package:xp_fake_play/xp_fake_play.dart';

/// The instant the tests stand at: 2026-10-13 12:00:00 UTC.
final testNow = DateTime.utc(2026, 10, 13, 12);

int get _seconds => testNow.millisecondsSinceEpoch ~/ 1000;

String _base64Url(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

/// An assertion for the fake server's token endpoint, signed by the test key.
/// [claims] and [header] replace the defaults field by field; a `null` value
/// removes the field.
String mint(
  Uri audience, {
  Map<String, Object?> claims = const {},
  Map<String, Object?> header = const {},
  String privateKeyPem = fakePlayPrivateKeyPem,
  bool tamper = false,
}) {
  final headerJson = <String, Object?>{'alg': 'RS256', 'typ': 'JWT', ...header}
    ..removeWhere((_, value) => value == null);
  final claimsJson = <String, Object?>{
    'iss': fakePlayClientEmail,
    'scope': fakePlayScope,
    'aud': '$audience',
    'iat': _seconds,
    'exp': _seconds + 3600,
    ...claims,
  }..removeWhere((_, value) => value == null);
  final signingInput =
      '${_base64Url(utf8.encode(jsonEncode(headerJson)))}.'
      '${_base64Url(utf8.encode(jsonEncode(claimsJson)))}';
  final signer = RSASigner(
    SHA256Digest(),
    '0609608648016503040201',
  )..init(true, PrivateKeyParameter<RSAPrivateKey>(_privateKey(privateKeyPem)));
  final signature = signer
      .generateSignature(Uint8List.fromList(utf8.encode(signingInput)))
      .bytes;
  if (tamper) signature[0] ^= 1;
  return '$signingInput.${_base64Url(signature)}';
}

RSAPrivateKey _privateKey(String pem) {
  final body = pem
      .split('\n')
      .where((line) => !line.startsWith('-----') && line.isNotEmpty)
      .join();
  final info = ASN1Parser(base64.decode(body)).nextObject() as ASN1Sequence;
  final key =
      ASN1Parser(info.elements![2].valueBytes).nextObject() as ASN1Sequence;
  BigInt at(int index) => (key.elements![index] as ASN1Integer).integer!;
  return RSAPrivateKey(at(1), at(3), at(4), at(5));
}

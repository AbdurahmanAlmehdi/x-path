import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';
import 'package:xp_fake_firebase/xp_fake_firebase.dart';
import 'package:xp_fake_play/xp_fake_play.dart';

String _base64Url(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

/// An assertion for the fake server's token endpoint, signed by the test key
/// of `xp_fake_play` (a copy of its helper: it is not exported).
String mint(
  Uri audience, {
  Map<String, Object?> claims = const {},
  String privateKeyPem = fakePlayPrivateKeyPem,
}) {
  final seconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final headerJson = {'alg': 'RS256', 'typ': 'JWT'};
  final claimsJson = <String, Object?>{
    'iss': fakePlayClientEmail,
    'scope': fakeFirebaseScope,
    'aud': '$audience',
    'iat': seconds,
    'exp': seconds + 3600,
    ...claims,
  };
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

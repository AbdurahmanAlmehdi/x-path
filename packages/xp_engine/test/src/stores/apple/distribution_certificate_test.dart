import 'dart:convert';

import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../helpers/apple_identity_fixtures.dart';

void main() {
  final der = base64.decode(testDistributionCertificate);

  test('reads the serial number, expiry and common name', () {
    final certificate = DistributionCertificate.fromDer(der);

    expect(certificate.serialNumber, 'A1B2C3D4E5F');
    expect(certificate.notAfter, DateTime.utc(2126, 10, 1, 14, 21, 57));
    expect(
      certificate.commonName,
      'Apple Distribution: XPath Test (TEAM123456)',
    );
    expect(certificate.der, der);
  });

  test('reads a UTCTime expiry and a subject without a common name', () {
    final certificate = DistributionCertificate.fromDer(
      base64.decode(shortDistributionCertificate),
    );

    expect(certificate.serialNumber, 'FF');
    expect(certificate.notAfter, DateTime.utc(2026, 11, 24, 14, 22, 10));
    expect(certificate.commonName, isNull);
  });

  test('matches a serial number however App Store Connect pads it', () {
    final certificate = DistributionCertificate.fromDer(der);

    expect(certificate.hasSerial('0a1b2c3d4e5f'), isTrue);
    expect(certificate.hasSerial('A1B2C3D4E5F'), isTrue);
    expect(certificate.hasSerial('A1B2C3D4E5E'), isFalse);
  });

  test('takes base64 DER and PEM', () {
    final pem =
        '-----BEGIN CERTIFICATE-----\n'
        '${base64.encode(der)}\n'
        '-----END CERTIFICATE-----\n';

    expect(
      DistributionCertificate.fromText(pem),
      DistributionCertificate.fromDer(der),
    );
    expect(
      DistributionCertificate.fromText(' $testDistributionCertificate\n'),
      DistributionCertificate.fromDer(der),
    );
    expect(
      DistributionCertificate.fromText(base64.encode(utf8.encode(pem))),
      DistributionCertificate.fromDer(der),
      reason: 'a PEM file the app sent as base64',
    );
  });

  test('refuses what is not a certificate', () {
    for (final bytes in [
      <int>[],
      [0x30],
      [0x30, 0x85, 1, 1, 1, 1, 1],
      [0x30, 0x80],
      [0x30, 0x05, 0x02, 0x01],
      [0x31, 0x00],
      der.sublist(0, 100),
      utf8.encode('-----BEGIN CERTIFICATE-----'),
    ]) {
      expect(
        () => DistributionCertificate.fromDer(bytes),
        throwsFormatException,
        reason: '$bytes',
      );
    }
    expect(
      () => DistributionCertificate.fromText('not base64!'),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'The certificate is neither base64 DER nor PEM.',
        ),
      ),
    );
  });

  test('refuses a validity that is not a time', () {
    final broken = [...der];
    // The tag of notBefore, a UTCTime (0x17), becomes an INTEGER.
    final at = _indexOf(broken, [0x17, 0x0d, 0x32, 0x36]);
    broken[at] = 0x02;

    expect(
      () => DistributionCertificate.fromDer(broken),
      throwsFormatException,
    );
  });
}

int _indexOf(List<int> bytes, List<int> needle) {
  for (var i = 0; i <= bytes.length - needle.length; i++) {
    var found = true;
    for (var j = 0; j < needle.length; j++) {
      if (bytes[i + j] != needle[j]) {
        found = false;
        break;
      }
    }
    if (found) return i;
  }
  throw StateError('not found');
}

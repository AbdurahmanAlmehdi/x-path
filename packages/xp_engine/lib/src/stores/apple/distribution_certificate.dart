import 'dart:convert';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';

/// What the engine reads of an Apple Distribution certificate (X.509, DER):
/// enough to find it in App Store Connect and to know when it expires. The
/// signature is not checked; App Store Connect's list is what says the
/// certificate is the team's.
class DistributionCertificate extends Equatable {
  /// Creates the certificate.
  const new({
    required this.der,
    required this.serialNumber,
    required this.notAfter,
    this.commonName,
  });

  /// Reads [der].
  ///
  /// Throws a [FormatException] if it is not an X.509 certificate.
  factory fromDer(List<int> der) {
    final bytes = Uint8List.fromList(der);
    try {
      final certificate = _Der(bytes).sequence();
      final tbs = _Der(certificate).sequence();
      final fields = _Der(tbs);
      if (fields.peek == 0xa0) fields.next(); // [0] version
      final serial = fields.expect(0x02);
      fields
        ..sequence() // signature algorithm
        ..sequence(); // issuer
      final validity = _Der(fields.sequence())..time(); // notBefore
      final notAfter = validity.time();
      final subject = fields.sequence();
      return DistributionCertificate(
        der: bytes,
        serialNumber: _hex(serial),
        notAfter: notAfter,
        commonName: _commonName(subject),
      );
    } on _Malformed {
      throw const FormatException('The certificate is not X.509 (DER).');
    }
  }

  /// Reads a certificate sent as base64 DER or as a PEM block.
  ///
  /// Throws a [FormatException] if it is neither, or not X.509.
  factory fromText(String text) {
    final pem = RegExp(
      '-----BEGIN CERTIFICATE-----(.*?)-----END CERTIFICATE-----',
      dotAll: true,
    ).firstMatch(text);
    final body = (pem?.group(1) ?? text).replaceAll(RegExp(r'\s'), '');
    final List<int> der;
    try {
      der = base64.decode(base64.normalize(body));
    } on FormatException {
      throw const FormatException(
        'The certificate is neither base64 DER nor PEM.',
      );
    }
    return DistributionCertificate.fromDer(der);
  }

  /// The certificate, DER.
  final Uint8List der;

  /// The serial number in upper-case hexadecimal without leading zeros, as
  /// App Store Connect lists it.
  final String serialNumber;

  /// When it expires, in UTC.
  final DateTime notAfter;

  /// The common name of its subject: "Apple Distribution: Acme Ltd
  /// (TEAM123456)".
  final String? commonName;

  /// Whether [serial], as App Store Connect writes it, is this serial number.
  bool hasSerial(String serial) => _unpadded(serial) == serialNumber;

  static String _hex(Uint8List bytes) => _unpadded(
    [for (final byte in bytes) byte.toRadixString(16).padLeft(2, '0')].join(),
  );

  static String _unpadded(String hex) =>
      hex.toUpperCase().replaceFirst(RegExp('^0+(?=.)'), '');

  /// The common name (2.5.4.3) of the X.501 name [name], if it has one.
  static String? _commonName(Uint8List name) {
    final sets = _Der(name);
    while (!sets.isDone) {
      final attributes = _Der(sets.expect(0x31));
      while (!attributes.isDone) {
        final attribute = _Der(attributes.sequence());
        final type = attribute.expect(0x06);
        final value = attribute.next();
        if (type.length == 3 &&
            type[0] == 0x55 &&
            type[1] == 0x04 &&
            type[2] == 0x03) {
          return utf8.decode(value, allowMalformed: true);
        }
      }
    }
    return null;
  }

  @override
  List<Object?> get props => [serialNumber, notAfter, commonName];
}

class _Malformed implements Exception {
  const new();
}

/// Reads DER elements one after another.
class _Der {
  new(this._bytes);

  final Uint8List _bytes;
  var _at = 0;
  var _tag = 0;

  bool get isDone => _at >= _bytes.length;

  int get peek => isDone ? -1 : _bytes[_at];

  /// The contents of the next element, whatever its tag.
  Uint8List next() {
    if (isDone) throw const _Malformed();
    _tag = _bytes[_at++];
    var length = _byte();
    if (length & 0x80 != 0) {
      final count = length & 0x7f;
      if (count == 0 || count > 4) throw const _Malformed();
      length = 0;
      for (var i = 0; i < count; i++) {
        length = (length << 8) | _byte();
      }
    }
    if (_at + length > _bytes.length) throw const _Malformed();
    final contents = Uint8List.sublistView(_bytes, _at, _at + length);
    _at += length;
    return contents;
  }

  /// The contents of the next element, which must have [tag].
  Uint8List expect(int tag) {
    final contents = next();
    if (_tag != tag) throw const _Malformed();
    return contents;
  }

  Uint8List sequence() => expect(0x30);

  /// The next UTCTime or GeneralizedTime, in UTC.
  DateTime time() {
    final contents = next();
    final text = ascii.decode(contents, allowInvalid: true);
    final match = switch (_tag) {
      0x17 => RegExp(r'^(\d{2})(\d{10})Z$').firstMatch(text),
      0x18 => RegExp(r'^(\d{4})(\d{10})Z$').firstMatch(text),
      _ => null,
    };
    if (match == null) throw const _Malformed();
    var year = int.parse(match.group(1)!);
    // RFC 5280: a two-digit year from 50 is 19xx, else 20xx.
    if (_tag == 0x17) year += year >= 50 ? 1900 : 2000;
    final rest = match.group(2)!;
    int at(int index) => int.parse(rest.substring(index, index + 2));
    return DateTime.utc(year, at(0), at(2), at(4), at(6), at(8));
  }

  int _byte() {
    if (isDone) throw const _Malformed();
    return _bytes[_at++];
  }
}

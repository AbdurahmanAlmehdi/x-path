import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_fake_asc/xp_fake_asc.dart';

/// A secp384r1 key: valid PKCS#8, wrong curve for ES256.
const _p384 = '''
-----BEGIN PRIVATE KEY-----
MIG2AgEAMBAGByqGSM49AgEGBSuBBAAiBIGeMIGbAgEBBDBQKn1sGjEIHpEe89CR
b2jnWZR2uzkFK5LlLQ78igiu+xFH+/6ewYZq+CQ4KpgL3/qhZANiAAS7iKkxiwXL
LG9y2HXy3hN1UoNW2lThsiT7M6Imb0pgUvlws+L+lTolcQto/X5KA8L6JyLWVn5o
w0mukczJAw+fH+hTb+pt6UgTJTfKwdHpxMH+UtshTD1VdGpwnbbcCBM=
-----END PRIVATE KEY-----
''';

/// The same key as [fakeAscPrivateKeyPem] in the SEC1 form (`openssl ecparam
/// -genkey`), which App Store Connect does not hand out.
const _sec1 = '''
-----BEGIN EC PRIVATE KEY-----
MHcCAQEEIA6sKDcK8dl3FsRjUcZak+TxRj5rS7ZS4Mcj75MX4FnUoAoGCCqGSM49
AwEHoUQDQgAEYFCZZ2s6Sid2UnX6xZO+a/Wz6g6MrcfefTQ9YgwpZ//Zx5Z1Jfdc
iM6eZxQusPBzuBFQt7DOzsnZH6R7xcW+Mw==
-----END EC PRIVATE KEY-----
''';

String _hex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('Es256Signer', () {
    test('signs the RFC 6979 vector (A.2.5, P-256, SHA-256, "sample")', () {
      final signer = Es256Signer.fromScalar(
        BigInt.parse(
          'C9AFA9D845BA75166B5C215767B1D6934E50C3DB36E89B127B8A622B120F6721',
          radix: 16,
        ),
      );

      final signature = signer.sign(utf8.encode('sample'));

      expect(
        _hex(signature),
        'efd48b2aacb6a8fd1140dd9cd45e81d69d2c877b56aaf991c34d0ea84eaf3716'
        'f7cb1c942d657c41d436c7a1b6e29f65f3e900dbb9aff4064dc4ab2f843acda8',
      );
    });

    test('signs 64 bytes, r then s, and is deterministic', () {
      final signer = Es256Signer.fromPem(fakeAscPrivateKeyPem);

      final first = signer.sign(utf8.encode('message'));

      expect(first, hasLength(64));
      expect(signer.sign(utf8.encode('message')), first);
      expect(signer.sign(utf8.encode('other')), isNot(first));
    });

    test('rejects a scalar outside the curve', () {
      expect(
        () => Es256Signer.fromScalar(BigInt.zero),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => Es256Signer.fromScalar(BigInt.one << 256),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('Es256Signer.fromPem', () {
    test('reads the .p8 that OpenSSL made', () {
      expect(() => Es256Signer.fromPem(fakeAscPrivateKeyPem), returnsNormally);
    });

    test('reads it with Windows line endings and blank lines', () {
      final crlf = fakeAscPrivateKeyPem.replaceAll('\n', '\r\n\r\n');

      expect(() => Es256Signer.fromPem(crlf), returnsNormally);
    });

    test('refuses another curve', () {
      expect(
        () => Es256Signer.fromPem(_p384),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('not a P-256 key'),
          ),
        ),
      );
    });

    for (final (name, pem) in [
      ('text', 'not a key'),
      ('empty', ''),
      ('SEC1', _sec1),
      ('truncated PKCS#8', '-----BEGIN PRIVATE KEY-----\nMIGH\n-----END'),
    ]) {
      test('refuses $name without printing it', () {
        expect(
          () => Es256Signer.fromPem(pem),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              allOf(contains('.p8'), isNot(contains('MIGH'))),
            ),
          ),
        );
      });
    }
  });

  group('against OpenSSL', () {
    test('a signature verifies with openssl dgst -verify', () async {
      final directory = await Directory.systemTemp.createTemp('es256_');
      addTearDown(() => directory.delete(recursive: true));
      const message = 'header.payload';
      final raw = Es256Signer.fromPem(fakeAscPrivateKeyPem)
          .sign(utf8.encode(message));
      File('${directory.path}/pub.pem').writeAsStringSync(fakeAscPublicKeyPem);
      File('${directory.path}/message').writeAsStringSync(message);
      File('${directory.path}/sig.der').writeAsBytesSync(_der(raw));

      final result = await Process.run('openssl', [
        'dgst',
        '-sha256',
        '-verify',
        '${directory.path}/pub.pem',
        '-signature',
        '${directory.path}/sig.der',
        '${directory.path}/message',
      ]);

      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect('${result.stdout}', contains('Verified OK'));
    }, tags: 'process');
  });
}

/// The DER form `openssl` wants of a raw `r || s` signature.
Uint8List _der(Uint8List raw) {
  List<int> integer(List<int> bytes) {
    var start = 0;
    while (start < bytes.length - 1 && bytes[start] == 0) {
      start++;
    }
    final value = bytes.sublist(start);
    final body = value.first >= 0x80 ? [0, ...value] : value;
    return [0x02, body.length, ...body];
  }

  final body = [...integer(raw.sublist(0, 32)), ...integer(raw.sublist(32))];
  return Uint8List.fromList([0x30, body.length, ...body]);
}

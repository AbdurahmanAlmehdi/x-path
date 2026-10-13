import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_fake_asc/xp_fake_asc.dart';
import 'package:xp_fake_play/xp_fake_play.dart';

/// `printf 'eyJhbGciOiJSUzI1NiJ9.e30' | openssl dgst -sha256 -sign key.pem`
/// with the key of [fakePlayPrivateKeyPem], base64 encoded.
const _openSslSignature =
    'PD3MP4xisQNMGU0oZtLwwZ5E3AqsAdXRzqzvFDg9umcf9fUCrLuA9UQkx28YobVnD6DsAC8e'
    'CFNW/v/BwePfH1bhcZC5fR04IEfPUEc4b8BMRqbTlZ24YRklZxcwUizZfaPfisMUHGmgtUfn'
    '5DXJNnkuKA+t4LU74/dv2CZusCJpWmn4YycSGYmwjLe2K/Kd3+DLc3+Ium/Sh853UrZeofvB'
    'Vg1zhjj3k8d9HEc6fx8MJ3kF7PMO2tmUpWUc9NwjPiksIw3iIrOXZb1Yu9AUpgfO720QZOW/'
    'SRHBXm0n2WmptD52NV+uyT5TIKVvkvoBBPRXf1/bbY2283z4lv6zag==';

const _message = 'eyJhbGciOiJSUzI1NiJ9.e30';

/// The start of a PKCS#8 key, cut short.
const _truncated =
    '-----BEGIN PRIVATE KEY-----\nMIIE\n-----END PRIVATE KEY-----';

void main() {
  group('Rs256Signer', () {
    test('signs exactly like openssl dgst -sha256 -sign', () {
      final signature = Rs256Signer.fromPem(fakePlayPrivateKeyPem)
          .sign(utf8.encode(_message));

      expect(base64.encode(signature), _openSslSignature);
    });

    test('signs 256 bytes for a 2048-bit key, deterministically', () {
      final signer = Rs256Signer.fromPem(fakePlayPrivateKeyPem);

      final first = signer.sign(utf8.encode('message'));

      expect(first, hasLength(256));
      expect(signer.sign(utf8.encode('message')), first);
      expect(signer.sign(utf8.encode('other')), isNot(first));
    });

    test('reads a key with Windows line endings and blank lines', () {
      final pem = fakePlayPrivateKeyPem.replaceAll('\n', '\r\n\r\n');

      expect(
        base64.encode(Rs256Signer.fromPem(pem).sign(utf8.encode(_message))),
        _openSslSignature,
      );
    });

    for (final (name, pem, message) in [
      ('an EC key', fakeAscPrivateKeyPem, 'not an RSA key'),
      ('text', 'nope', 'unencrypted PKCS#8'),
      ('a truncated key', _truncated, 'unencrypted PKCS#8'),
      ('an empty key', '', 'unencrypted PKCS#8'),
    ]) {
      test('refuses $name without printing it', () {
        expect(
          () => Rs256Signer.fromPem(pem),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              allOf(contains(message), isNot(contains('MIIE'))),
            ),
          ),
        );
      });
    }
  });

  group('against OpenSSL', () {
    test('a signature verifies with openssl dgst -verify', () async {
      final directory = await Directory.systemTemp.createTemp('rs256_');
      addTearDown(() => directory.delete(recursive: true));
      File('${directory.path}/pub.pem').writeAsStringSync(fakePlayPublicKeyPem);
      File('${directory.path}/message').writeAsStringSync('header.payload');
      File('${directory.path}/sig').writeAsBytesSync(
        Rs256Signer.fromPem(fakePlayPrivateKeyPem)
            .sign(utf8.encode('header.payload')),
      );

      final result = await Process.run('openssl', [
        'dgst',
        '-sha256',
        '-verify',
        '${directory.path}/pub.pem',
        '-signature',
        '${directory.path}/sig',
        '${directory.path}/message',
      ]);

      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect('${result.stdout}', contains('Verified OK'));
    }, tags: 'process');
  });
}

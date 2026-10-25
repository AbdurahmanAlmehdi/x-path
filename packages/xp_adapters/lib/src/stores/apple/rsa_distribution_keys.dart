import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';
import 'package:xp_adapters/src/stores/play/rs256_signer.dart';
import 'package:xp_engine/xp_engine.dart';

/// `rsaEncryption`.
const _rsaEncryption = [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01];

/// `sha256WithRSAEncryption`.
const _sha256WithRsa = [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x0b];

/// `commonName` (2.5.4.3).
const _commonName = [0x55, 0x04, 0x03];

/// [DistributionKeys] with pointycastle: an RSA key of [bits] bits (2048, as
/// Apple asks), PKCS#8, and a PKCS#10 request signed with SHA-256, which is
/// what Keychain Access makes on a Mac.
class RsaDistributionKeys implements DistributionKeys {
  /// Creates the generator; [bits] is smaller only in tests.
  const new({this.bits = 2048});

  /// The size of the keys.
  final int bits;

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
    final algorithm = _sequence([
      _tlv(0x06, _rsaEncryption),
      _tlv(0x05, const []),
    ]);
    final p = private.p!;
    final q = private.q!;
    final d = private.privateExponent!;
    final pkcs8 = _sequence([
      _integer(BigInt.zero),
      algorithm,
      _tlv(
        0x04,
        _sequence([
          _integer(BigInt.zero),
          _integer(public.modulus!),
          _integer(public.exponent!),
          _integer(d),
          _integer(p),
          _integer(q),
          _integer(d % (p - BigInt.one)),
          _integer(d % (q - BigInt.one)),
          _integer(q.modInverse(p)),
        ]),
      ),
    ]);
    final privateKeyPem = _pem('PRIVATE KEY', pkcs8);
    final info = _sequence([
      _integer(BigInt.zero),
      _sequence([
        _tlv(
          0x31,
          _sequence([
            _tlv(0x06, _commonName),
            _tlv(0x0c, utf8.encode(commonName)),
          ]),
        ),
      ]),
      _sequence([
        algorithm,
        _bitString(
          _sequence([_integer(public.modulus!), _integer(public.exponent!)]),
        ),
      ]),
      _tlv(0xa0, const []),
    ]);
    final signature = Rs256Signer.fromPem(privateKeyPem).sign(info);
    final request = _sequence([
      info,
      _sequence([_tlv(0x06, _sha256WithRsa), _tlv(0x05, const [])]),
      _bitString(signature),
    ]);
    return (
      privateKeyPem: privateKeyPem,
      csrPem: _pem('CERTIFICATE REQUEST', request),
    );
  }

  static List<int> _sequence(List<List<int>> elements) =>
      _tlv(0x30, [for (final element in elements) ...element]);

  static List<int> _bitString(List<int> bytes) => _tlv(0x03, [0, ...bytes]);

  /// A positive INTEGER: big-endian, with a leading zero when the high bit is
  /// set.
  static List<int> _integer(BigInt value) {
    final bytes = <int>[];
    var rest = value;
    do {
      bytes.insert(0, (rest & BigInt.from(0xff)).toInt());
      rest >>= 8;
    } while (rest > BigInt.zero);
    if (bytes.first & 0x80 != 0) bytes.insert(0, 0);
    return _tlv(0x02, bytes);
  }

  static List<int> _tlv(int tag, List<int> content) {
    final length = content.length;
    final header = length < 0x80
        ? [length]
        : () {
            final bytes = <int>[];
            for (var rest = length; rest > 0; rest >>= 8) {
              bytes.insert(0, rest & 0xff);
            }
            return [0x80 | bytes.length, ...bytes];
          }();
    return [tag, ...header, ...content];
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

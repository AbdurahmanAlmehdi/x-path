import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:xp_engine/xp_engine.dart';
import 'package:xp_secrets/src/encrypted_file/master_key.dart';
import 'package:xp_secrets/src/tracking_secret_store.dart';

/// Keeps secrets in one encrypted file, for machines without a Keychain.
///
/// The file, `secrets.enc` in the data directory, holds a JSON object of all
/// secrets, sealed with XChaCha20-Poly1305 under one master key (see
/// [MasterKeySource]). Layout, all in one file:
///
/// | bytes | content                                              |
/// |-------|------------------------------------------------------|
/// | 5     | magic, `XPSEC`                                       |
/// | 1     | format version, `1`                                  |
/// | 24    | nonce, fresh random bytes for every write            |
/// | n     | ciphertext                                           |
/// | 16    | Poly1305 tag                                         |
///
/// The magic and the version are authenticated as associated data, so a file
/// cannot be passed off as another format. Every write goes to a temporary
/// file with mode 0600 that is then renamed over the old file. One process
/// owns the file: operations run one at a time.
///
/// A master key that is missing or does not open the file throws a
/// [SecretsLockedException].
class EncryptedFileSecretStore extends TrackingSecretStore {
  /// Creates a store in `dataDir`.
  ///
  /// `credentialsDirectory` is `$CREDENTIALS_DIRECTORY`. `runner` sets file
  /// permissions.
  new({
    required String dataDir,
    required ProcessRunner runner,
    String? credentialsDirectory,
  }) : _runner = runner,
       _path = p.join(dataDir, fileName),
       _masterKey = MasterKeySource(
         dataDir: dataDir,
         runner: runner,
         credentialsDirectory: credentialsDirectory,
       );

  /// The name of the secrets file in the data directory.
  static const fileName = 'secrets.enc';

  static const _magic = 'XPSEC';
  static const _version = 1;
  static final List<int> _header = [...ascii.encode(_magic), _version];
  static const _nonceLength = 24;
  static const _macLength = 16;

  final ProcessRunner _runner;
  final String _path;
  final MasterKeySource _masterKey;
  final _algorithm = Xchacha20.poly1305Aead();
  Future<void> _tail = Future.value();

  @override
  Future<String?> read(String key) => track(() async {
    checkKey(key);
    return await _serialized(() async => (await _readAll())?[key]);
  });

  @override
  Future<void> write(String key, String value) => track(() async {
    checkKey(key);
    await _serialized(() async {
      final secrets = await _readAll() ?? {};
      secrets[key] = value;
      await _save(secrets);
    });
  });

  @override
  Future<void> delete(String key) => track(() async {
    checkKey(key);
    await _serialized(() async {
      final secrets = await _readAll();
      if (secrets == null || secrets.remove(key) == null) return;
      await _save(secrets);
    });
  });

  /// Runs [operation] after every earlier operation has finished.
  Future<T> _serialized<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  /// Every secret, or `null` if nothing was ever written.
  Future<Map<String, String>?> _readAll() async {
    final file = File(_path);
    if (!file.existsSync()) return null;
    final key = await _masterKey.load(createIfMissing: false);
    final bytes = await file.readAsBytes();
    if (bytes.length < _header.length + _nonceLength + _macLength) {
      throw const SecretStoreException('The secrets file is truncated.');
    }
    if (String.fromCharCodes(bytes.sublist(0, _magic.length)) != _magic) {
      throw const SecretStoreException(
        'The secrets file is not an XPath file.',
      );
    }
    final version = bytes[_magic.length];
    if (version != _version) {
      throw SecretStoreException(
        'The secrets file has format version $version; this engine reads '
        'version $_version.',
      );
    }
    final nonceEnd = _header.length + _nonceLength;
    final macStart = bytes.length - _macLength;
    final box = SecretBox(
      bytes.sublist(nonceEnd, macStart),
      nonce: bytes.sublist(_header.length, nonceEnd),
      mac: Mac(bytes.sublist(macStart)),
    );
    final List<int> plain;
    try {
      plain = await _algorithm.decrypt(
        box,
        secretKey: SecretKey(key),
        aad: _header,
      );
    } on SecretBoxAuthenticationError {
      throw const SecretsLockedException(
        'The master key does not open the secrets file: it is the wrong key, '
        'or the file was changed.',
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(plain));
    } on FormatException {
      throw const SecretStoreException('The secrets file is not valid.');
    }
    if (decoded is! Map<String, dynamic> ||
        decoded.values.any((value) => value is! String)) {
      throw const SecretStoreException('The secrets file is not valid.');
    }
    return decoded.cast<String, String>();
  }

  Future<void> _save(Map<String, String> secrets) async {
    final key = await _masterKey.load(
      createIfMissing: !File(_path).existsSync(),
    );
    final nonce = _algorithm.newNonce();
    final box = await _algorithm.encrypt(
      utf8.encode(jsonEncode(secrets)),
      secretKey: SecretKey(key),
      nonce: nonce,
      aad: _header,
    );
    await writePrivateFile(_runner, _path, [
      ..._header,
      ...box.nonce,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
  }
}

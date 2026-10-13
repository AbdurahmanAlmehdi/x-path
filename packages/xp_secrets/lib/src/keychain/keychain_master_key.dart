import 'dart:math';

import 'package:xp_engine/xp_engine.dart';
import 'package:xp_secrets/src/encrypted_file/master_key.dart';

/// A [MasterKeySource] that keeps the key in the macOS Keychain.
///
/// The key is [masterKeyLength] random bytes, stored through a
/// [SecretStore] (the macOS store gives it its own
/// scope, so it is a separate Keychain item from any credential) under the
/// account [account]. It is created on first use, when the file it will
/// encrypt does not exist yet. The key stays in the Keychain; only the
/// encrypted file is on disk, so a locked Keychain locks the file too.
class KeychainMasterKeySource implements MasterKeySource {
  /// Creates a source over `store`.
  new({required this._store, this.account = defaultAccount, Random? random})
    : _random = random ?? Random.secure();

  /// The Keychain account of the key.
  static const defaultAccount = 'secrets-file-key';

  /// The Keychain account this source reads and writes.
  final String account;

  final SecretStore _store;
  final Random _random;
  List<int>? _cached;

  @override
  Future<List<int>> load({required bool createIfMissing}) async {
    final cached = _cached;
    if (cached != null) return cached;
    final stored = await _store.readBytes(account);
    if (stored != null) {
      if (stored.length != masterKeyLength) {
        throw SecretsLockedException(
          'The master key in the Keychain must be exactly $masterKeyLength '
          'bytes, not ${stored.length}.',
        );
      }
      return _cached = stored;
    }
    if (!createIfMissing) {
      throw const SecretsLockedException(
        'The master key is missing from the Keychain, but secrets exist.',
      );
    }
    final key = List.generate(masterKeyLength, (_) => _random.nextInt(256));
    await _store.writeBytes(account, key);
    return _cached = key;
  }
}

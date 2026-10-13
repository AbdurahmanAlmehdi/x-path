import 'dart:typed_data';

import 'package:xp_engine/xp_engine.dart';
import 'package:xp_secrets/src/tracking_secret_store.dart';

/// Keeps small secrets in one store and large ones in another (ADR 0008).
///
/// On macOS the small store is the Keychain, which cannot take a value of more
/// than about 3 KB, and the large store is the encrypted file whose key is in
/// the Keychain. A value goes to the large store when its base64 form is
/// longer than [maxSmallEncodedLength] characters, which is the form the
/// Keychain store sends.
///
/// A key lives in exactly one store. A write goes to the store that fits and
/// then deletes the key from the other one, so a secret that grows or shrinks
/// moves. Should a crash come between the two steps, the key is in both until
/// the next write or delete of it; [readBytes] asks the small store first.
///
/// Both stores must be reachable for the composite to be: a failure of either
/// that says "locked" locks this store, and every operation runs after the
/// previous one has finished, so a moving secret is never half there.
class SizeRoutedSecretStore extends TrackingSecretStore {
  /// Creates a store that keeps what fits in `small` there and the rest in
  /// `large`.
  new({required this._small, required this._large});

  /// The longest base64 form that stays in the small store: 2 KB. A
  /// `security -i` command line is limited to 4094 bytes, and the command,
  /// the service, the key and the keychain path take a few hundred of those.
  static const maxSmallEncodedLength = 2048;

  final SecretStore _small;
  final SecretStore _large;

  /// The length of the base64 form of [byteCount] bytes.
  static int encodedLength(int byteCount) => (byteCount + 2) ~/ 3 * 4;

  @override
  Future<Uint8List?> readBytes(String key) => track(() async {
    checkKey(key);
    return await serialized(() async {
      return await _small.readBytes(key) ?? await _large.readBytes(key);
    });
  });

  @override
  Future<void> writeBytes(String key, List<int> value) => track(() async {
    checkKey(key);
    await serialized(() async {
      final isLarge = encodedLength(value.length) > maxSmallEncodedLength;
      final (target, other) = isLarge ? (_large, _small) : (_small, _large);
      await target.writeBytes(key, value);
      await other.delete(key);
    });
  });

  @override
  Future<void> delete(String key) => track(() async {
    checkKey(key);
    await serialized(() async {
      await _small.delete(key);
      await _large.delete(key);
    });
  });
}

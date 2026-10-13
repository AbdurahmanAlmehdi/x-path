import 'dart:async';
import 'dart:convert';

import 'package:xp_engine/xp_engine.dart';
import 'package:xp_secrets/src/utf8_text.dart';

/// A [SecretStore] that follows its own [SecretsStatus].
///
/// A subclass implements [readBytes], [writeBytes] and [delete], wrapping each
/// in [track]: a [SecretsLockedException] makes the status
/// [SecretsStatus.locked] and any other outcome that reached the secrets makes
/// it [SecretsStatus.unlocked]. The text methods [read] and [write] are the
/// UTF-8 view of the bytes.
abstract class TrackingSecretStore implements SecretStore {
  final StreamController<SecretsStatus> _changes =
      StreamController<SecretsStatus>.broadcast(sync: true);
  SecretsStatus _status = SecretsStatus.unlocked;
  Future<void> _tail = Future.value();

  @override
  SecretsStatus get status => _status;

  @override
  Stream<SecretsStatus> get statusChanges => _changes.stream;

  @override
  Future<String?> read(String key) async {
    final bytes = await readBytes(key);
    if (bytes == null) return null;
    try {
      return decodeUtf8Exactly(bytes);
    } on FormatException {
      throw const SecretStoreException(
        'The secret is binary, not text: read it with readBytes.',
      );
    }
  }

  @override
  Future<void> write(String key, String value) =>
      writeBytes(key, utf8.encode(value));

  /// Runs [operation] and updates [status] from how it ended.
  Future<T> track<T>(Future<T> Function() operation) async {
    try {
      final result = await operation();
      _setStatus(SecretsStatus.unlocked);
      return result;
    } on SecretsLockedException {
      _setStatus(SecretsStatus.locked);
      rethrow;
    }
  }

  /// Runs [operation] after every earlier call of this method has finished.
  Future<T> serialized<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  /// Throws an [ArgumentError] unless [key] is a usable secret name: not
  /// empty and free of control characters such as line breaks.
  void checkKey(String key) {
    if (key.isEmpty) throw ArgumentError.value(key, 'key', 'is empty');
    if (key.runes.any((r) => r < 0x20 || r == 0x7f)) {
      throw ArgumentError.value(key, 'key', 'contains a control character');
    }
  }

  void _setStatus(SecretsStatus status) {
    if (_status == status) return;
    _status = status;
    _changes.add(status);
  }
}

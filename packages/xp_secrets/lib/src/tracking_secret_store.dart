import 'dart:async';

import 'package:xp_engine/xp_engine.dart';

/// A [SecretStore] that follows its own [SecretsStatus].
///
/// A subclass wraps each operation in [track]: a [SecretsLockedException]
/// makes the status [SecretsStatus.locked] and any other outcome that reached
/// the secrets makes it [SecretsStatus.unlocked].
abstract class TrackingSecretStore implements SecretStore {
  final StreamController<SecretsStatus> _changes =
      StreamController<SecretsStatus>.broadcast(sync: true);
  SecretsStatus _status = SecretsStatus.unlocked;

  @override
  SecretsStatus get status => _status;

  @override
  Stream<SecretsStatus> get statusChanges => _changes.stream;

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

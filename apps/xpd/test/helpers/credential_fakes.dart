import 'dart:convert';
import 'dart:typed_data';

import 'package:xp_engine/xp_engine.dart';

/// A [SecretStore] in memory that keeps bytes as bytes.
class BytesSecretStore implements SecretStore {
  /// What is stored, by key.
  final values = <String, Uint8List>{};

  /// Set to make every call fail with it.
  SecretStoreException? failure;

  @override
  SecretsStatus get status => failure is SecretsLockedException
      ? SecretsStatus.locked
      : SecretsStatus.unlocked;

  @override
  Stream<SecretsStatus> get statusChanges => const Stream.empty();

  /// The text under [key], without going through the store.
  String? text(String key) {
    final value = values[key];
    return value == null ? null : utf8.decode(value);
  }

  @override
  Future<String?> read(String key) async {
    final failure = this.failure;
    if (failure != null) throw failure;
    return text(key);
  }

  @override
  Future<void> write(String key, String value) =>
      writeBytes(key, utf8.encode(value));

  @override
  Future<Uint8List?> readBytes(String key) async {
    final failure = this.failure;
    if (failure != null) throw failure;
    return values[key];
  }

  @override
  Future<void> writeBytes(String key, List<int> value) async {
    final failure = this.failure;
    if (failure != null) throw failure;
    values[key] = Uint8List.fromList(value);
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

/// An [OutputMasker] that remembers what it was told to hide.
class RecordingMasker implements OutputMasker {
  /// The secrets, in the order they were added.
  final secrets = <String>[];

  @override
  void add(String secret) => secrets.add(secret);

  @override
  StreamMasker newStream() => const NoMasking().newStream();
}

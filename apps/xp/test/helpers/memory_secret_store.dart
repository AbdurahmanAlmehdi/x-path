import 'dart:convert';
import 'dart:typed_data';

import 'package:xp_engine/xp_engine.dart';

/// A [SecretStore] in memory.
class MemorySecretStore implements SecretStore {
  /// What is stored, by key.
  final values = <String, List<int>>{};

  /// Set to make every call fail with it.
  SecretStoreException? failure;

  @override
  SecretsStatus get status => SecretsStatus.unlocked;

  @override
  Stream<SecretsStatus> get statusChanges => const Stream.empty();

  @override
  Future<String?> read(String key) async {
    if (failure case final error?) throw error;
    final value = values[key];
    return value == null ? null : utf8.decode(value);
  }

  @override
  Future<void> write(String key, String value) =>
      writeBytes(key, utf8.encode(value));

  @override
  Future<Uint8List?> readBytes(String key) async {
    if (failure case final error?) throw error;
    final value = values[key];
    return value == null ? null : Uint8List.fromList(value);
  }

  @override
  Future<void> writeBytes(String key, List<int> value) async {
    if (failure case final error?) throw error;
    values[key] = List.of(value);
  }

  @override
  Future<void> delete(String key) async => values.remove(key);
}

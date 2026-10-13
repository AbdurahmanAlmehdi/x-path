import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:xp_engine/xp_engine.dart';

/// A [SecretStore] in memory, for tests.
class MemorySecretStore implements SecretStore {
  /// What is stored, by key.
  final values = <String, String>{};

  @override
  SecretsStatus get status => SecretsStatus.unlocked;

  @override
  Stream<SecretsStatus> get statusChanges => const Stream.empty();

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<Uint8List?> readBytes(String key) async {
    final value = values[key];
    return value == null ? null : Uint8List.fromList(utf8.encode(value));
  }

  @override
  Future<void> writeBytes(String key, List<int> value) async =>
      values[key] = utf8.decode(value);

  @override
  Future<void> delete(String key) async => values.remove(key);
}

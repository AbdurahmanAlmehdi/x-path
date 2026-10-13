import 'dart:typed_data';

import 'package:xp_engine/xp_engine.dart';

/// A [SecretStore] in memory that can be made to fail, for tests.
class MemorySecretStore implements SecretStore {
  /// What is stored, by key.
  final values = <String, Uint8List>{};

  /// If set, every operation throws it.
  SecretStoreException? failure;

  /// Every operation so far, as `read key`, `write key` or `delete key`.
  final operations = <String>[];

  @override
  SecretsStatus get status => SecretsStatus.unlocked;

  @override
  Stream<SecretsStatus> get statusChanges => const Stream.empty();

  @override
  Future<String?> read(String key) => throw UnimplementedError();

  @override
  Future<void> write(String key, String value) => throw UnimplementedError();

  @override
  Future<Uint8List?> readBytes(String key) async {
    operations.add('read $key');
    if (failure case final failure?) throw failure;
    return values[key];
  }

  @override
  Future<void> writeBytes(String key, List<int> value) async {
    operations.add('write $key');
    if (failure case final failure?) throw failure;
    values[key] = Uint8List.fromList(value);
  }

  @override
  Future<void> delete(String key) async {
    operations.add('delete $key');
    if (failure case final failure?) throw failure;
    values.remove(key);
  }
}

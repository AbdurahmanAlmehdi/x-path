import 'package:xp_engine/xp_engine.dart';

/// A [SecretStore] in memory.
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
  Future<void> delete(String key) async => values.remove(key);
}

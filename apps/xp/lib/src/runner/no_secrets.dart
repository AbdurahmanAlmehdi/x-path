import 'dart:typed_data';

import 'package:xp_engine/xp_engine.dart';

/// The secrets of git on a runner: none. The runner reaches GitHub with its
/// own SSH key, and holds no token of the engine (ADR 0009).
class NoSecrets implements SecretStore {
  const new();

  @override
  SecretsStatus get status => SecretsStatus.unlocked;

  @override
  Stream<SecretsStatus> get statusChanges => const Stream.empty();

  @override
  Future<String?> read(String key) async => null;

  @override
  Future<Uint8List?> readBytes(String key) async => null;

  @override
  Future<void> write(String key, String value) async {}

  @override
  Future<void> writeBytes(String key, List<int> value) async {}

  @override
  Future<void> delete(String key) async {}
}

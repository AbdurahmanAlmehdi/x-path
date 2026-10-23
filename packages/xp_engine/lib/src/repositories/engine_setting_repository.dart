/// Settings of the engine itself, one text value per key, for example the
/// runner URL (`RunnerService.runnerUrlKey`).
abstract interface class EngineSettingRepository {
  /// The value of [key], or `null` when it is not set.
  Future<String?> read(String key);

  /// Sets [key] to [value], or clears it for `null`.
  Future<void> write(String key, String? value);
}

/// An [EngineSettingRepository] that forgets everything on exit.
class InMemoryEngineSettingRepository implements EngineSettingRepository {
  final _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
  }
}

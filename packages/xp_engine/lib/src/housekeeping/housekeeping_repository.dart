import 'package:xp_api/xp_api.dart';

/// Where housekeeping keeps its settings and the time of its last run.
///
/// `xp_adapters` has the SQLite implementation.
abstract interface class HousekeepingRepository {
  /// The retention the owner set, or the defaults.
  Future<RetentionSettings> retention();

  /// Stores [settings].
  Future<void> saveRetention(RetentionSettings settings);

  /// When the logs were last pruned, or `null` if never.
  Future<DateTime?> lastLogPrune();

  /// Records that the logs were pruned at [at].
  Future<void> saveLogPrune(DateTime at);
}

/// A [HousekeepingRepository] that forgets everything on exit.
class InMemoryHousekeepingRepository implements HousekeepingRepository {
  RetentionSettings _retention = const RetentionSettings();
  DateTime? _lastLogPrune;

  @override
  Future<RetentionSettings> retention() async => _retention;

  @override
  Future<void> saveRetention(RetentionSettings settings) async =>
      _retention = settings;

  @override
  Future<DateTime?> lastLogPrune() async => _lastLogPrune;

  @override
  Future<void> saveLogPrune(DateTime at) async => _lastLogPrune = at;
}

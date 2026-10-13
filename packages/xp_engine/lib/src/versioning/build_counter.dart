import 'package:xp_engine/src/versioning/versioning_exceptions.dart';

/// The build number counter of each app (D-11).
///
/// There is one counter per app, in the database. It only goes up: a number
/// that was handed out is never given back, even if the build that was meant
/// to use it failed, because the stores reject a number they have seen.
///
/// `xp_adapters` has the SQLite implementation.
abstract interface class BuildCounterRepository {
  /// Hands out the next build number of the app at [appPath] in [projectId]:
  /// one more than the larger of the stored counter and [seed], and stores it.
  ///
  /// The read and the write are one atomic step, so two jobs never get the
  /// same number.
  ///
  /// Throws an [UnknownAppException] if the project has no such app.
  Future<int> allocate({
    required String projectId,
    required String appPath,
    required int seed,
  });
}

/// A [BuildCounterRepository] that forgets everything on exit.
class InMemoryBuildCounterRepository implements BuildCounterRepository {
  /// Creates a repository that knows [apps] as `(projectId, appPath)` pairs,
  /// each starting at its counter in [counters] or 0.
  new(
    Iterable<(String, String)> apps, {
    Map<(String, String), int> counters = const {},
  }) : _counters = {for (final app in apps) app: counters[app] ?? 0};

  final Map<(String, String), int> _counters;

  /// The counter of an app, without changing it.
  int counterOf(String projectId, String appPath) =>
      _counters[(projectId, appPath)] ??
      (throw UnknownAppException(projectId, appPath));

  @override
  Future<int> allocate({
    required String projectId,
    required String appPath,
    required int seed,
  }) async {
    RangeError.checkNotNegative(seed, 'seed');
    final current = counterOf(projectId, appPath);
    return _counters[(projectId, appPath)] =
        (current > seed ? current : seed) + 1;
  }
}

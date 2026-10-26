import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/releases/release_record.dart';

/// Where releases are kept.
///
/// `xp_adapters` has the SQLite implementation.
abstract interface class ReleaseRepository {
  /// The release [id], or `null`.
  Future<ReleaseRecord?> get(String id);

  /// The releases, newest first; only those of [projectId], of the app at
  /// [appPath] and in one of [states] if given.
  Future<List<ReleaseRecord>> list({
    String? projectId,
    String? appPath,
    Set<ReleaseState>? states,
  });

  /// Stores a new release.
  Future<void> create(ReleaseRecord release);

  /// Replaces the stored release that has the id of [release].
  Future<void> update(ReleaseRecord release);

  /// Adds [event] to the history of the release [releaseId] (U7b).
  Future<void> addEvent(String releaseId, ReleaseEvent event);

  /// The history of the release [releaseId], oldest first.
  Future<List<ReleaseEvent>> events(String releaseId);
}

/// A [ReleaseRepository] that forgets everything on exit.
class InMemoryReleaseRepository implements ReleaseRepository {
  final _records = <String, ReleaseRecord>{};
  final _events = <String, List<ReleaseEvent>>{};

  @override
  Future<ReleaseRecord?> get(String id) async => _records[id];

  @override
  Future<List<ReleaseRecord>> list({
    String? projectId,
    String? appPath,
    Set<ReleaseState>? states,
  }) async => [
    for (final record in _records.values.toList().reversed)
      if ((projectId == null || record.projectId == projectId) &&
          (appPath == null || record.appPath == appPath) &&
          (states == null || states.contains(record.state)))
        record,
  ];

  @override
  Future<void> create(ReleaseRecord release) async {
    if (_records.containsKey(release.id)) {
      throw StateError('Release ${release.id} exists.');
    }
    _records[release.id] = release;
  }

  @override
  Future<void> update(ReleaseRecord release) async {
    if (!_records.containsKey(release.id)) {
      throw StateError('No release ${release.id}.');
    }
    _records[release.id] = release;
  }

  @override
  Future<void> addEvent(String releaseId, ReleaseEvent event) async =>
      _events.putIfAbsent(releaseId, () => []).add(event);

  @override
  Future<List<ReleaseEvent>> events(String releaseId) async =>
      [...?_events[releaseId]]..sort((a, b) => a.at.compareTo(b.at));
}

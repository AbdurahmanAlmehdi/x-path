import 'package:xp_engine/src/artifacts/artifact_record.dart';

/// Where the records of stored artifacts are kept.
///
/// `xp_adapters` has the SQLite implementation.
abstract interface class ArtifactRepository {
  /// Stores [record], replacing the one with the same id.
  Future<void> save(ArtifactRecord record);

  /// The artifact [id], or `null`.
  Future<ArtifactRecord?> get(String id);

  /// The artifact of [jobId] that is stored at [path], or `null`.
  Future<ArtifactRecord?> findByPath(String jobId, String path);

  /// The artifacts of [jobId], oldest first.
  Future<List<ArtifactRecord>> forJob(String jobId);

  /// Sets whether the artifact [id] is pinned and returns it as it is now, or
  /// returns `null` if there is none.
  Future<ArtifactRecord?> setPinned(String id, {required bool pinned});
}

/// An [ArtifactRepository] that forgets everything on exit.
class InMemoryArtifactRepository implements ArtifactRepository {
  final _records = <String, ArtifactRecord>{};

  @override
  Future<void> save(ArtifactRecord record) async =>
      _records[record.id] = record;

  @override
  Future<ArtifactRecord?> get(String id) async => _records[id];

  @override
  Future<ArtifactRecord?> findByPath(String jobId, String path) async =>
      _records.values
          .where((record) => record.jobId == jobId && record.path == path)
          .firstOrNull;

  @override
  Future<List<ArtifactRecord>> forJob(String jobId) async => [
    for (final record in _records.values)
      if (record.jobId == jobId) record,
  ];

  @override
  Future<ArtifactRecord?> setPinned(String id, {required bool pinned}) async {
    final record = _records[id]?.withPinned(pinned: pinned);
    if (record != null) _records[id] = record;
    return record;
  }
}

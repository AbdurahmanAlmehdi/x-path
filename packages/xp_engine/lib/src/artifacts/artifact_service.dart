import 'package:xp_engine/src/artifacts/artifact_exceptions.dart';
import 'package:xp_engine/src/artifacts/artifact_record.dart';
import 'package:xp_engine/src/artifacts/artifact_repository.dart';
import 'package:xp_engine/src/artifacts/artifact_store.dart';
import 'package:xp_engine/src/jobs/job_exceptions.dart';
import 'package:xp_engine/src/jobs/job_repository.dart';

/// An artifact with the stream of its bytes.
class ArtifactDownload {
  /// Creates a download.
  const new(this.record, this.content);

  /// The artifact; its `size` is the length of [content].
  final ArtifactRecord record;

  /// The bytes of the file.
  final Stream<List<int>> content;
}

/// What clients can do with the artifacts of the engine: list, read, download,
/// pin.
class ArtifactService {
  /// Creates the service.
  const new({
    required this._repository,
    required this._store,
    required this._jobs,
  });

  final ArtifactRepository _repository;
  final ArtifactStore _store;
  final JobRepository _jobs;

  /// The artifacts of the job [jobId], oldest first.
  ///
  /// Throws a [JobNotFoundException] if there is no such job.
  Future<List<ArtifactRecord>> forJob(String jobId) async {
    if (await _jobs.get(jobId) == null) throw JobNotFoundException(jobId);
    return await _repository.forJob(jobId);
  }

  /// The artifact [id].
  ///
  /// Throws an [ArtifactNotFoundException] if there is none.
  Future<ArtifactRecord> get(String id) async =>
      await _repository.get(id) ?? (throw _missing(id));

  /// The artifact [id] and its bytes.
  ///
  /// Throws an [ArtifactNotFoundException] if there is no such artifact, or
  /// its file is no longer in the store.
  Future<ArtifactDownload> download(String id) async {
    final record = await get(id);
    if (!await _store.exists(record.path)) {
      throw ArtifactNotFoundException(
        'The file of artifact $id (${record.name}) is no longer in the '
        'artifact store.',
      );
    }
    return ArtifactDownload(record, _store.read(record.path));
  }

  /// Pins the artifact [id] so that it is kept when the engine frees up space,
  /// and returns it. Pinning a pinned artifact changes nothing.
  ///
  /// Throws an [ArtifactNotFoundException] if there is none.
  Future<ArtifactRecord> pin(String id) => _setPinned(id, pinned: true);

  /// Unpins the artifact [id] and returns it.
  ///
  /// Throws an [ArtifactNotFoundException] if there is none.
  Future<ArtifactRecord> unpin(String id) => _setPinned(id, pinned: false);

  Future<ArtifactRecord> _setPinned(String id, {required bool pinned}) async =>
      await _repository.setPinned(id, pinned: pinned) ?? (throw _missing(id));

  ArtifactNotFoundException _missing(String id) =>
      ArtifactNotFoundException('There is no artifact $id.');
}

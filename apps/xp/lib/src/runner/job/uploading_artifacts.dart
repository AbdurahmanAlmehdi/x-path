import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_engine/xp_engine.dart';

/// Uploads a file a job made to the engine's artifact store
/// (`PUT /runners/jobs/{id}/artifacts/{name}`). [content] makes a new stream
/// of the file each time it is called, so that an upload can be tried again.
typedef ArtifactUpload = Future<void> Function({
  required String jobId,
  required String leaseId,
  required String name,
  required ArtifactKind kind,
  required Stream<List<int>> Function() content,
  required int size,
  required String sha256,
});

/// The upload of artifacts with [client], whose token is the credential of the
/// runner.
ArtifactUpload uploadThrough(XpClient client) =>
    ({
      required jobId,
      required leaseId,
      required name,
      required kind,
      required content,
      required size,
      required sha256,
    }) async {
      await client.uploadRunnerArtifact(
        jobId: jobId,
        name: name,
        leaseId: leaseId,
        kind: kind,
        content: content(),
        size: size,
        sha256: sha256,
      );
    };

/// Makes the [ArtifactUpload] that tries again when the connection to the
/// engine fails (not when the engine refuses: a lease that is lost or a wrong
/// digest do not get better), waiting [delays] between the attempts.
ArtifactUpload retrying(
  ArtifactUpload upload, {
  List<Duration> delays = const [Duration(seconds: 2), Duration(seconds: 8)],
  Future<void> Function(Duration) wait = Future.delayed,
}) =>
    ({
      required jobId,
      required leaseId,
      required name,
      required kind,
      required content,
      required size,
      required sha256,
    }) async {
      for (var attempt = 0; ; attempt++) {
        try {
          return await upload(
            jobId: jobId,
            leaseId: leaseId,
            name: name,
            kind: kind,
            content: content,
            size: size,
            sha256: sha256,
          );
        } on ConnectionException {
          if (attempt == delays.length) rethrow;
          await wait(delays[attempt]);
        }
      }
    };

/// The records of the artifacts a leased job makes. A runner keeps the files
/// of the job on its own disk, for the steps that read them back (the compiled
/// config check, the manifest); each file that is recorded is also uploaded to
/// the engine, with its SHA-256, before the step that made it ends. The
/// engine's store is where later jobs (the uploads to the stores) find them.
class UploadingArtifactRepository extends InMemoryArtifactRepository {
  /// Creates the repository over the job's local [_store].
  new({required this._store, required this._upload, required this._leaseId});

  final ArtifactStore _store;
  final ArtifactUpload _upload;
  final String _leaseId;

  @override
  Future<void> save(ArtifactRecord record) async {
    await _upload(
      jobId: record.jobId,
      leaseId: _leaseId,
      name: p.basename(record.path),
      kind: record.kind,
      content: () => _store.read(record.path),
      size: record.size,
      sha256: record.sha256,
    );
    await super.save(record);
  }
}

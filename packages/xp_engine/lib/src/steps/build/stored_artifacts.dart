import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/artifacts/artifact_record.dart';
import 'package:xp_engine/src/artifacts/artifact_recorder.dart';
import 'package:xp_engine/src/artifacts/artifact_repository.dart';
import 'package:xp_engine/src/artifacts/artifact_store.dart';
import 'package:xp_engine/src/artifacts/digest.dart';

/// The artifact called [name] of the job [jobId] if the store still holds a
/// file with the SHA-256 recorded for it, else `null`.
///
/// This is the idempotency check of the steps that store files: "sha in DB".
Future<ArtifactRecord?> intactArtifact({
  required ArtifactRepository repository,
  required ArtifactStore store,
  required String jobId,
  required String name,
  required ArtifactKind kind,
}) async {
  final path = ArtifactRecorder.pathOf(jobId, name);
  final record = await repository.findByPath(jobId, path);
  if (record == null ||
      record.kind != kind ||
      !await store.exists(path) ||
      await sha256OfStream(store.read(path)) != record.sha256) {
    return null;
  }
  return record;
}

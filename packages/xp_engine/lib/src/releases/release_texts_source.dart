import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/jobs/job_repository.dart';
import 'package:xp_engine/src/releases/release_repository.dart';

/// The language Google Play gets the "What's new" text of a release in.
const releaseTextsLanguage = 'en-US';

/// The texts of the release a job uploads (U7b), read when the upload runs,
/// so that a text typed on the release while it builds reaches the stores.
abstract interface class ReleaseTextsSource {
  /// The texts of the release of the job [jobId]; `null` for a job of no
  /// release.
  Future<ReleaseTexts?> ofJob(String jobId);
}

/// The [ReleaseTextsSource] of the engine: the release the job belongs to.
class JobReleaseTexts implements ReleaseTextsSource {
  /// Creates the source.
  const new({required this._jobs, required this._releases});

  final JobRepository _jobs;
  final ReleaseRepository _releases;

  @override
  Future<ReleaseTexts?> ofJob(String jobId) async {
    final releaseId = (await _jobs.get(jobId))?.releaseId;
    if (releaseId == null) return null;
    final release = await _releases.get(releaseId);
    if (release == null) return null;
    return ReleaseTexts(
      whatsNew: release.whatsNew,
      whatToTest: release.whatToTest,
    );
  }
}

/// A [ReleaseTextsSource] with the texts the test gives it.
class FakeReleaseTextsSource implements ReleaseTextsSource {
  /// Creates a source that answers [texts] for every job.
  new([this.texts]);

  /// The answer.
  ReleaseTexts? texts;

  @override
  Future<ReleaseTexts?> ofJob(String jobId) async => texts;
}

import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/jobs/job_record.dart';

/// A job of a release with its steps, as the job repository has them.
class JobProgress {
  /// Creates the pair.
  const new(this.job, this.steps);

  /// The job.
  final JobRecord job;

  /// Its steps, in order.
  final List<StepRecord> steps;

  /// The result of the step of [kind] that succeeded, if one did.
  Map<String, dynamic>? resultOf(String kind) => steps
      .where((step) => step.kind == kind && step.state == StepState.succeeded)
      .map((step) => step.result)
      .nonNulls
      .firstOrNull;
}

/// The step types that build the app.
const Set<String> _buildKinds = {
  'build.android',
  'build.ios',
  'shorebird.release',
};

/// The step type that uploads to each store.
const Map<String, ReleaseStore> _uploadKinds = {
  'upload.appStore': ReleaseStore.apple,
  'upload.play': ReleaseStore.play,
};

/// What the jobs of one build of a release have done, read from their steps.
///
/// The release state follows from it (`ReleaseService.sync`): `building` once
/// a build step started, `uploaded` once every store the release targets has
/// its upload, and the branch, the tag and the pull request are recorded as
/// their steps succeed. Nothing here talks to a store.
class BuildProgress extends Equatable {
  /// Creates a reading.
  const new({
    this.buildStarted = false,
    this.uploaded = const {},
    this.branch,
    this.tag,
    this.headSha,
    this.prNumber,
    this.prUrl,
    this.failure,
  });

  /// Reads the progress of [jobs], the jobs of one build of one release.
  factory of(List<JobProgress> jobs) {
    final steps = [for (final job in jobs) ...job.steps];
    final uploads = <ReleaseStore, List<StepRecord>>{};
    for (final step in steps) {
      final store = _uploadKinds[step.kind];
      if (store != null) uploads.putIfAbsent(store, () => []).add(step);
    }
    Map<String, dynamic>? result(String kind) =>
        [for (final job in jobs) job.resultOf(kind)].nonNulls.firstOrNull;
    final branch = result('git.releaseBranch');
    final tag = result('git.tag');
    final pr = result('github.createPr');
    final failed = jobs
        .where(
          (job) =>
              job.job.state == JobState.failed ||
              job.job.state == JobState.cancelled,
        )
        .firstOrNull;
    return BuildProgress(
      buildStarted: steps.any(
        (step) =>
            _buildKinds.contains(step.kind) && step.state != StepState.pending,
      ),
      uploaded: {
        for (final MapEntry(:key, :value) in uploads.entries)
          if (value.every((step) => step.state.isDone)) key,
      },
      branch: branch?['name'] as String?,
      tag: tag?['name'] as String?,
      headSha: tag?['sha'] as String?,
      prNumber: pr?['number'] as int?,
      prUrl: pr?['url'] as String?,
      failure: failed == null ? null : _describe(failed.job),
    );
  }

  static String _describe(JobRecord job) {
    final message = job.message;
    return '${job.name ?? job.id} ${job.state.wire}'
        '${message == null ? '' : ': $message'}';
  }

  /// Whether a build step started.
  final bool buildStarted;

  /// The stores whose upload steps are all done.
  final Set<ReleaseStore> uploaded;

  /// The release branch, once `git.releaseBranch` made it.
  final String? branch;

  /// The tag, once `git.tag` made it.
  final String? tag;

  /// The commit the tag names.
  final String? headSha;

  /// The pull request, once `github.createPr` opened it.
  final int? prNumber;

  /// Where to see it.
  final String? prUrl;

  /// What stopped the build: the first job that failed or was cancelled.
  final String? failure;

  @override
  List<Object?> get props => [
    buildStarted,
    uploaded,
    branch,
    tag,
    headSha,
    prNumber,
    prUrl,
    failure,
  ];
}

/// What the run that merges the pull request of a release has done.
class MergeProgress extends Equatable {
  /// Creates a reading.
  const new({this.mergeCommit, this.ended = false, this.failure});

  /// Reads the progress of [jobs], the jobs of the merge run.
  factory of(List<JobProgress> jobs) {
    final merged = [for (final job in jobs) job.resultOf('github.mergePr')]
        .nonNulls
        .firstOrNull;
    final stopped = jobs
        .where(
          (job) =>
              job.job.state == JobState.failed ||
              job.job.state == JobState.cancelled,
        )
        .firstOrNull;
    return MergeProgress(
      mergeCommit: merged?['sha'] as String?,
      ended: stopped != null,
      failure: stopped?.job.message,
    );
  }

  /// The merge commit, once the merge step succeeded.
  final String? mergeCommit;

  /// Whether a job of the run failed or was cancelled (a denied gate
  /// included), so that nothing merges the pull request any more.
  final bool ended;

  /// Why, as the job said.
  final String? failure;

  @override
  List<Object?> get props => [mergeCommit, ended, failure];
}

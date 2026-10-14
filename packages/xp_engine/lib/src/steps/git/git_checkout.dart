import 'package:equatable/equatable.dart';
import 'package:xp_engine/src/git/git_service.dart';
import 'package:xp_engine/src/jobs/job_repository.dart';
import 'package:xp_engine/src/json_fields.dart';
import 'package:xp_engine/src/steps/step.dart';
import 'package:xp_engine/src/steps/step_context.dart';
import 'package:xp_engine/src/versioning/release_worktree.dart';

/// Where a job's worktree is cut from.
class GitCheckoutInput extends Equatable {
  /// Creates the input.
  const new({required this.worktree, this.commitFromJob});

  /// Reads the input from its stored form.
  ///
  /// Throws a [FormatException] if a field is missing or of the wrong type.
  factory fromJson(Map<String, dynamic> json) => GitCheckoutInput(
    worktree: ReleaseWorktree.fromJson(requiredObject(json, 'worktree')),
    commitFromJob: optionalString(json, 'commitFromJob'),
  );

  /// The worktree to make: its directory, mirror and dispatched commit.
  final ReleaseWorktree worktree;

  /// A job of the same run whose version commit this job starts from, so that
  /// every job of a release builds the very commit the first job made
  /// (`version.bump`). Without it the job starts from the dispatched commit.
  final String? commitFromJob;

  /// The stored form.
  Map<String, dynamic> toJson() => {
    'worktree': worktree.toJson(),
    'commitFromJob': ?commitFromJob,
  };

  @override
  List<Object?> get props => [worktree, commitFromJob];
}

/// What `git.checkout` made.
class GitCheckoutResult extends Equatable {
  /// Creates the result.
  const new({required this.path, required this.sha});

  /// The directory of the worktree.
  final String path;

  /// The commit that is checked out.
  final String sha;

  @override
  List<Object?> get props => [path, sha];
}

/// Checks out the commit of a job in a worktree of its own (`git.checkout`,
/// D-05): the first step of every job, so that a job waiting in the queue
/// holds no directory and a job that needs the version commit of an earlier
/// job of its run starts from that commit.
class GitCheckoutStep extends Step<GitCheckoutInput, GitCheckoutResult> {
  /// Creates the step.
  const new({required this._git, required this._jobs});

  final GitService _git;
  final JobRepository _jobs;

  @override
  String get kind => 'git.checkout';

  @override
  bool sideEffectOf(GitCheckoutInput input) => false;

  @override
  GitCheckoutInput decodeInput(Map<String, dynamic> json) =>
      GitCheckoutInput.fromJson(json);

  @override
  Map<String, dynamic> encodeInput(GitCheckoutInput input) => input.toJson();

  @override
  Map<String, dynamic> encodeResult(GitCheckoutResult result) => {
    'path': result.path,
    'sha': result.sha,
  };

  @override
  Future<StepOutcome<GitCheckoutResult>> run(
    GitCheckoutInput input,
    StepContext context,
  ) async {
    final target = input.worktree;
    final source = input.commitFromJob;
    final String sha;
    if (source == null) {
      sha = target.sha;
    } else {
      final commit = await _versionCommitOf(source);
      if (commit == null) {
        return StepFailed(
          'Job $source made no version commit, so this job has nothing to '
          'start from.',
        );
      }
      sha = commit;
    }
    final name = target.path.split('/').last;
    final worktree = await _git.createWorktree(
      target.mirror,
      name: name,
      sha: sha,
    );
    if (worktree.path != target.path) {
      return StepFailed(
        'The worktree is at ${worktree.path}, not at ${target.path} where '
        'the steps of this job look for it.',
      );
    }
    return StepSucceeded(GitCheckoutResult(path: worktree.path, sha: sha));
  }

  Future<String?> _versionCommitOf(String jobId) =>
      versionCommitOf(_jobs, jobId);
}

/// The commit the `version.bump` step of the job [jobId] made or found, or
/// `null` if the job has none.
Future<String?> versionCommitOf(JobRepository jobs, String jobId) async {
  for (final step in await jobs.steps(jobId)) {
    if (step.kind == 'version.bump' && step.state.isDone) {
      return step.result?['commit'] as String?;
    }
  }
  return null;
}

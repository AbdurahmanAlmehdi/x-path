import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/git/github_client.dart';
import 'package:xp_engine/src/git/github_exceptions.dart';
import 'package:xp_engine/src/git/github_models.dart';
import 'package:xp_engine/src/json_fields.dart';
import 'package:xp_engine/src/releases/release_repository.dart';
import 'package:xp_engine/src/steps/step.dart';
import 'package:xp_engine/src/steps/step_context.dart';

/// Which release pull request to merge.
class GitHubMergePrInput extends Equatable {
  /// Creates the input.
  const new({required this.releaseId, required this.githubRepoId});

  /// Reads the input from its stored form.
  ///
  /// Throws a [FormatException] if a field is missing or of the wrong type.
  factory fromJson(Map<String, dynamic> json) {
    final repo = json['githubRepoId'];
    if (repo is! int) {
      throw const FormatException('"githubRepoId" must be a number.');
    }
    return GitHubMergePrInput(
      releaseId: requiredString(json, 'releaseId'),
      githubRepoId: repo,
    );
  }

  /// The release whose pull request is merged.
  final String releaseId;

  /// The GitHub id of the repository (D-05).
  final int githubRepoId;

  /// The stored form.
  Map<String, dynamic> toJson() => {
    'releaseId': releaseId,
    'githubRepoId': githubRepoId,
  };

  @override
  List<Object?> get props => [releaseId, githubRepoId];
}

/// What `github.mergePr` merged.
class GitHubMergePrResult extends Equatable {
  /// Creates the result.
  const new({
    required this.number,
    required this.sha,
    required this.alreadyMerged,
  });

  /// The pull request.
  final int number;

  /// The merge commit.
  final String sha;

  /// Whether the pull request was merged before this step looked.
  final bool alreadyMerged;

  @override
  List<Object?> get props => [number, sha, alreadyMerged];
}

/// Merges the pull request of a release with a merge commit (`github.mergePr`,
/// ADR 0007).
///
/// A merge is a gated action (D-13): the `release-merge` workflow puts
/// `gate: merge` in front of this step, and it never runs without the owner's
/// approval. The step itself checks again that the release is `live` (every
/// store targeted is on sale), merges only the commit that was released
/// (`sha` is the head that was tagged, so a push to the branch since is
/// refused), and never picks another merge method: a repository that forbids
/// merge commits reports GitHub's error.
///
/// The step has a side effect. `alreadyDone` is the state of the pull
/// request: merged already.
class GitHubMergePrStep extends Step<GitHubMergePrInput, GitHubMergePrResult> {
  /// Creates the step.
  const new({required this.github, required this.releases});

  /// GitHub.
  final GitHubClient github;

  /// Where the releases are.
  final ReleaseRepository releases;

  @override
  String get kind => 'github.mergePr';

  @override
  bool sideEffectOf(GitHubMergePrInput input) => true;

  @override
  GitHubMergePrInput decodeInput(Map<String, dynamic> json) =>
      GitHubMergePrInput.fromJson(json);

  @override
  Map<String, dynamic> encodeInput(GitHubMergePrInput input) => input.toJson();

  @override
  Map<String, dynamic> encodeResult(GitHubMergePrResult result) => {
    'number': result.number,
    'sha': result.sha,
    'alreadyMerged': result.alreadyMerged,
  };

  /// Done when the pull request is merged.
  @override
  Future<GitHubMergePrResult?> alreadyDone(
    GitHubMergePrInput input,
    StepContext context,
  ) async {
    final number = (await releases.get(input.releaseId))?.prNumber;
    if (number == null) return null;
    final repo = await github.getRepoById(input.githubRepoId);
    return _merged(await github.getPullRequest(repo, number));
  }

  GitHubMergePrResult? _merged(GitHubPullRequest pullRequest) =>
      pullRequest.state == GitHubPullRequestState.merged
      ? GitHubMergePrResult(
          number: pullRequest.number,
          sha: pullRequest.mergeCommitSha ?? pullRequest.headSha,
          alreadyMerged: true,
        )
      : null;

  @override
  Future<StepOutcome<GitHubMergePrResult>> run(
    GitHubMergePrInput input,
    StepContext context,
  ) async {
    final release = await releases.get(input.releaseId);
    final number = release?.prNumber;
    if (release == null || number == null) {
      return StepFailed(
        'The release ${input.releaseId} has no pull request to merge.',
      );
    }
    try {
      final repo = await github.getRepoById(input.githubRepoId);
      final pullRequest = await github.getPullRequest(repo, number);
      final merged = _merged(pullRequest);
      if (merged != null) return StepSucceeded(merged);
      if (release.state != ReleaseState.live) {
        return StepFailed(
          'The release ${release.id} is ${release.state.wire}: its pull '
          'request is merged once every store is live.',
        );
      }
      if (pullRequest.state == GitHubPullRequestState.closed) {
        return StepFailed('Pull request #$number was closed without a merge.');
      }
      final result = await github.mergePullRequest(
        repo,
        number,
        expectedHeadSha: release.headSha,
      );
      return StepSucceeded(
        GitHubMergePrResult(
          number: number,
          sha: result.sha,
          alreadyMerged: false,
        ),
      );
    } on GitHubException catch (error) {
      return StepFailed(
        'GitHub did not merge pull request #$number: ${error.message}',
      );
    }
  }
}

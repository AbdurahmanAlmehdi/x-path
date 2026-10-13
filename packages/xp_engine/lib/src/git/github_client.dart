import 'package:xp_engine/src/git/github_models.dart';

/// The key under which the GitHub token lives in the `SecretStore`.
const githubTokenSecretKey = 'github.token';

/// The parts of the GitHub API that XPath uses.
///
/// `xp_adapters` has the HTTP implementation. Every method throws a
/// `GitHubException` (or a subclass) when GitHub refuses, and a
/// `SecretStoreException` when the token cannot be read.
abstract interface class GitHubClient {
  /// The repository `owner/name`.
  ///
  /// If GitHub knows it under another name now, the result is the current
  /// repository and [GitHubRepo.renamedFrom] says what was asked for.
  Future<GitHubRepo> getRepo(String owner, String name);

  /// The repository with GitHub id [id], under whatever name it has now.
  Future<GitHubRepo> getRepoById(int id);

  /// Opens a pull request in [repo] from [head] into [base].
  Future<GitHubPullRequest> createPullRequest(
    GitHubRepo repo, {
    required String title,
    required String head,
    required String base,
    String? body,
  });

  /// The pull request [number] of [repo].
  Future<GitHubPullRequest> getPullRequest(GitHubRepo repo, int number);

  /// Merges the pull request [number] of [repo] with [method].
  ///
  /// If [expectedHeadSha] is given and the head has moved since, GitHub
  /// refuses with a `GitHubConflictException`.
  Future<GitHubMergeResult> mergePullRequest(
    GitHubRepo repo,
    int number, {
    GitHubMergeMethod method = GitHubMergeMethod.merge,
    String? expectedHeadSha,
  });
}

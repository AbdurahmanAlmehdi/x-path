import 'package:xp_engine/xp_engine.dart';

/// A [GitHubClient] that knows the repositories in [repos].
class FakeGitHub implements GitHubClient {
  /// Creates a client that knows [repos], by id.
  new(this.repos);

  /// The repositories.
  final Map<int, GitHubRepo> repos;

  /// Set to make every call fail with it.
  Exception? failure;

  @override
  Future<GitHubRepo> getRepo(String owner, String name) async {
    final failure = this.failure;
    if (failure != null) throw failure;
    return repos.values.firstWhere(
      (repo) => repo.fullName.toLowerCase() == '$owner/$name'.toLowerCase(),
      orElse: () => throw const GitHubNotFoundException('Not Found'),
    );
  }

  @override
  Future<GitHubRepo> getRepoById(int id) async {
    final failure = this.failure;
    if (failure != null) throw failure;
    return repos[id] ?? (throw const GitHubNotFoundException('Not Found'));
  }

  @override
  Future<GitHubPullRequest> createPullRequest(
    GitHubRepo repo, {
    required String title,
    required String head,
    required String base,
    String? body,
  }) => throw UnimplementedError();

  @override
  Future<GitHubPullRequest> getPullRequest(GitHubRepo repo, int number) =>
      throw UnimplementedError();

  @override
  Future<GitHubMergeResult> mergePullRequest(
    GitHubRepo repo,
    int number, {
    GitHubMergeMethod method = GitHubMergeMethod.merge,
    String? expectedHeadSha,
  }) => throw UnimplementedError();
}

/// A [GitService] that has mirrors and worktrees only on paper.
class FakeGit implements GitService {
  /// Set to make [fetch] fail with it.
  Exception? fetchFailure;

  @override
  Future<GitMirror> ensureMirror({
    required int githubRepoId,
    required String remoteUrl,
  }) async =>
      GitMirror(githubRepoId: githubRepoId, path: '/mirrors/$githubRepoId.git');

  @override
  Future<void> fetch(GitMirror mirror) async {
    final failure = fetchFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<String> resolveRef(GitMirror mirror, String ref) async => 'a' * 40;

  @override
  Future<GitWorktree> createWorktree(
    GitMirror mirror, {
    required String name,
    required String sha,
  }) async => GitWorktree(mirror: mirror, path: '/worktrees/$name', sha: sha);

  @override
  Future<void> removeWorktree(GitWorktree worktree) async {}

  @override
  Future<List<GitTagInfo>> listTags(GitMirror mirror) =>
      throw UnimplementedError();

  @override
  Future<List<String>> changedFiles(
    GitMirror mirror, {
    required String from,
    required String to,
  }) => throw UnimplementedError();

  @override
  Future<GitWorktreeStatus> status(GitWorktree worktree) =>
      throw UnimplementedError();

  @override
  Future<GitCommitResult> commit(
    GitWorktree worktree, {
    required String message,
    required List<String> paths,
  }) => throw UnimplementedError();

  @override
  Future<TagOutcome> createTag(
    GitMirror mirror, {
    required String name,
    required String sha,
    required String message,
  }) => throw UnimplementedError();

  @override
  Future<BranchOutcome> upsertBranch(
    GitMirror mirror, {
    required String name,
    required String sha,
  }) => throw UnimplementedError();

  @override
  Future<void> push(GitMirror mirror, {required List<String> refspecs}) =>
      throw UnimplementedError();
}

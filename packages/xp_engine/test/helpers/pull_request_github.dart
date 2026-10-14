import 'package:xp_engine/xp_engine.dart';

/// A [GitHubClient] with one repository and the pull requests of a release.
class PullRequestGitHub implements GitHubClient {
  /// Creates a client that knows [repo].
  new(this.repo);

  /// The repository.
  final GitHubRepo repo;

  /// The pull requests, by number.
  final pulls = <int, GitHubPullRequest>{};

  /// Set to make every call fail with it.
  GitHubException? failure;

  /// What the next merge throws, once.
  GitHubException? mergeFailure;

  /// Every call as `name arguments`, oldest first.
  final calls = <String>[];

  /// The merge method of every merge, oldest first.
  final methods = <GitHubMergeMethod>[];

  /// The commit every merge expected the head to be at, oldest first.
  final expectedHeads = <String?>[];

  void _check() {
    final error = failure;
    if (error != null) throw error;
  }

  @override
  Future<GitHubRepo> getRepo(String owner, String name) =>
      throw UnimplementedError();

  @override
  Future<GitHubRepo> getRepoById(int id) async {
    calls.add('getRepoById $id');
    _check();
    return repo;
  }

  @override
  Future<GitHubPullRequest> createPullRequest(
    GitHubRepo repo, {
    required String title,
    required String head,
    required String base,
    String? body,
  }) async {
    calls.add('createPullRequest $head $base $title');
    _check();
    final number = pulls.length + 1;
    return pulls[number] = GitHubPullRequest(
      number: number,
      title: title,
      state: GitHubPullRequestState.open,
      headRef: head,
      headSha: 'b' * 40,
      baseRef: base,
      htmlUrl: 'https://github.com/${repo.fullName}/pull/$number',
    );
  }

  @override
  Future<GitHubPullRequest> getPullRequest(GitHubRepo repo, int number) async {
    calls.add('getPullRequest $number');
    _check();
    return pulls[number] ?? (throw const GitHubNotFoundException('Not Found'));
  }

  @override
  Future<GitHubPullRequest?> findPullRequest(
    GitHubRepo repo, {
    required String head,
    required String base,
  }) async {
    calls.add('findPullRequest $head $base');
    _check();
    return pulls.values
        .where(
          (pull) =>
              pull.headRef == head &&
              pull.baseRef == base &&
              pull.state == GitHubPullRequestState.open,
        )
        .firstOrNull;
  }

  @override
  Future<GitHubMergeResult> mergePullRequest(
    GitHubRepo repo,
    int number, {
    GitHubMergeMethod method = GitHubMergeMethod.merge,
    String? expectedHeadSha,
  }) async {
    calls.add('mergePullRequest $number');
    methods.add(method);
    expectedHeads.add(expectedHeadSha);
    _check();
    final error = mergeFailure;
    if (error != null) {
      mergeFailure = null;
      throw error;
    }
    final pull = pulls[number]!;
    pulls[number] = GitHubPullRequest(
      number: number,
      title: pull.title,
      state: GitHubPullRequestState.merged,
      headRef: pull.headRef,
      headSha: pull.headSha,
      baseRef: pull.baseRef,
      htmlUrl: pull.htmlUrl,
      mergeCommitSha: 'c' * 40,
    );
    return GitHubMergeResult(sha: 'c' * 40, message: 'merged');
  }
}

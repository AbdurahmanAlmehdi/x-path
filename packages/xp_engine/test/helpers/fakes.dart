import 'package:xp_engine/xp_engine.dart';

/// A [GitHubClient] that knows a few repositories.
class FakeGitHubClient implements GitHubClient {
  /// Creates a client that knows [repos].
  new(this.repos);

  /// The repositories, by id.
  final Map<int, GitHubRepo> repos;

  /// Set to make every call fail with it.
  Exception? failure;

  /// Former names (lower case `owner/name`) and the id of the repository that
  /// has them now.
  final aliases = <String, int>{};

  /// The `owner/name` of every [getRepo] call.
  final lookups = <String>[];

  @override
  Future<GitHubRepo> getRepo(String owner, String name) async {
    lookups.add('$owner/$name');
    final failure = this.failure;
    if (failure != null) throw failure;
    final renamed = repos[aliases['$owner/$name'.toLowerCase()]];
    if (renamed != null) {
      return GitHubRepo(
        id: renamed.id,
        fullName: renamed.fullName,
        defaultBranch: renamed.defaultBranch,
        cloneUrl: renamed.cloneUrl,
        renamedFrom: '$owner/$name',
      );
    }
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
  Future<GitHubPullRequest?> findPullRequest(
    GitHubRepo repo, {
    required String head,
    required String base,
  }) => throw UnimplementedError();

  @override
  Future<GitHubMergeResult> mergePullRequest(
    GitHubRepo repo,
    int number, {
    GitHubMergeMethod method = GitHubMergeMethod.merge,
    String? expectedHeadSha,
  }) => throw UnimplementedError();
}

/// A [GitService] that records what it was asked and hands out worktrees at
/// fixed paths.
class FakeGitService implements GitService {
  /// Every call as `method argument`, oldest first.
  final calls = <String>[];

  /// The mirror remotes by mirror key, as last set.
  final remotes = <String, String>{};

  /// Set to make [fetch] fail with it.
  Exception? fetchFailure;

  /// What [createWorktree] hands out, by worktree name.
  final worktrees = <String, String>{};

  /// If set, [ensureMirror] waits for it.
  Future<void>? gate;

  /// The default branch [lsRemote] reads.
  String defaultBranch = 'main';

  /// Set to make [lsRemote] fail with it.
  Exception? lsRemoteFailure;

  @override
  Future<String> lsRemote(String url) async {
    calls.add('lsRemote $url');
    final failure = lsRemoteFailure;
    if (failure != null) throw failure;
    return defaultBranch;
  }

  @override
  Future<GitMirror> ensureMirror({
    required String key,
    required String remoteUrl,
  }) async {
    await gate;
    calls.add('ensureMirror $key');
    remotes[key] = remoteUrl;
    return GitMirror(key: key, path: '/mirrors/$key.git');
  }

  @override
  Future<void> fetch(GitMirror mirror) async {
    calls.add('fetch ${mirror.key}');
    final failure = fetchFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<String> resolveRef(GitMirror mirror, String ref) async {
    calls.add('resolveRef $ref');
    return 'a' * 40;
  }

  @override
  Future<GitWorktree> createWorktree(
    GitMirror mirror, {
    required String name,
    required String sha,
  }) async {
    calls.add('createWorktree $name');
    return GitWorktree(
      mirror: mirror,
      path: worktrees[name] ?? '/worktrees/$name',
      sha: sha,
    );
  }

  @override
  Future<void> removeWorktree(GitWorktree worktree) async {
    calls.add('removeWorktree ${worktree.path}');
  }

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
  Future<List<GitCommit>> commitsBetween(
    GitMirror mirror, {
    required String to,
    String? from,
    int limit = 500,
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

import 'package:xp_engine/xp_engine.dart';

/// A [GitService] over data the test sets: tags, changed files, the status of
/// the worktree, and branches that remember what was made.
class StubGit implements GitService {
  /// The tags of the mirror.
  final tags = <GitTagInfo>[];

  /// What [changedFiles] answers.
  List<String> changed = [];

  /// What [status] answers.
  GitWorktreeStatus statusResult = GitWorktreeStatus(headSha: 'a' * 40);

  /// The commit [commit] makes; `created: false` simulates nothing to commit.
  GitCommitResult commitResult = GitCommitResult(
    sha: 'c' * 40,
    tree: 't' * 40,
    created: true,
  );

  /// Branch name to commit, as [upsertBranch] left them.
  final branches = <String, String>{};

  /// Commits [upsertBranch] treats as descendants of what a branch has.
  final descendants = <String>{};

  /// Every call as `method detail`, oldest first.
  final calls = <String>[];

  /// If set, [commit] runs it first.
  void Function()? onCommit;

  @override
  Future<List<GitTagInfo>> listTags(GitMirror mirror) async {
    calls.add('listTags');
    return tags;
  }

  @override
  Future<List<String>> changedFiles(
    GitMirror mirror, {
    required String from,
    required String to,
  }) async {
    calls.add('changedFiles $from $to');
    return changed;
  }

  /// What [commitsBetween] answers.
  List<GitCommit> commits = [];

  @override
  Future<List<GitCommit>> commitsBetween(
    GitMirror mirror, {
    required String to,
    String? from,
    int limit = 500,
  }) async {
    calls.add('commitsBetween $from $to $limit');
    return commits;
  }

  @override
  Future<GitWorktreeStatus> status(GitWorktree worktree) async {
    calls.add('status');
    return statusResult;
  }

  @override
  Future<GitCommitResult> commit(
    GitWorktree worktree, {
    required String message,
    required List<String> paths,
  }) async {
    calls.add('commit $message ${paths.join(',')}');
    onCommit?.call();
    return commitResult;
  }

  @override
  Future<BranchOutcome> upsertBranch(
    GitMirror mirror, {
    required String name,
    required String sha,
  }) async {
    calls.add('upsertBranch $name $sha');
    final current = branches[name];
    if (current == sha) return BranchOutcome.unchanged;
    if (current != null && !descendants.contains(sha)) {
      throw GitBranchConflictException(
        branch: name,
        currentSha: current,
        requestedSha: sha,
      );
    }
    branches[name] = sha;
    return current == null ? BranchOutcome.created : BranchOutcome.updated;
  }

  @override
  Future<String> lsRemote(String url) => throw UnimplementedError();

  @override
  Future<GitMirror> ensureMirror({
    required String key,
    required String remoteUrl,
  }) async => GitMirror(key: key, path: '/mirrors/$key.git');

  @override
  Future<void> fetch(GitMirror mirror) => throw UnimplementedError();

  /// What [resolveRef] answers for a ref that is not a full commit id.
  final refs = <String, String>{};

  @override
  Future<String> resolveRef(GitMirror mirror, String ref) async =>
      RegExp(r'^[0-9a-f]{40}$').hasMatch(ref) ? ref : refs[ref] ?? 'a' * 40;

  @override
  Future<GitWorktree> createWorktree(
    GitMirror mirror, {
    required String name,
    required String sha,
  }) => throw UnimplementedError();

  @override
  Future<void> removeWorktree(GitWorktree worktree) =>
      throw UnimplementedError();

  @override
  Future<TagOutcome> createTag(
    GitMirror mirror, {
    required String name,
    required String sha,
    required String message,
  }) => throw UnimplementedError();

  @override
  Future<void> push(GitMirror mirror, {required List<String> refspecs}) =>
      throw UnimplementedError();
}

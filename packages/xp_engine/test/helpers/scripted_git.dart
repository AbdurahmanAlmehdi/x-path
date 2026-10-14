import 'package:xp_engine/xp_engine.dart';

/// A [GitService] over data the test sets, that records what it was asked.
class ScriptedGit implements GitService {
  /// What the refs resolve to; every other ref is not found.
  final refs = <String, String>{'main': 'a' * 40};

  /// The tags of the mirror, by name.
  final tags = <String, String>{};

  /// What [status] answers.
  GitWorktreeStatus statusResult = GitWorktreeStatus(headSha: 'b' * 40);

  /// Every call as `method detail`, oldest first.
  final calls = <String>[];

  /// The branches [upsertBranch] made.
  final branches = <String, String>{};

  /// The refspecs of every push.
  final pushed = <List<String>>[];

  /// If set, [fetch] throws it.
  Exception? fetchFailure;

  /// If set, [push] throws it.
  Exception? pushFailure;

  /// If set, [createWorktree] gives this path instead of its usual one.
  String? worktreePath;

  /// A hook that runs when a worktree is made.
  void Function(String name, String sha)? onWorktree;

  /// Where the worktree [name] of [mirror] is.
  static String pathOf(GitMirror mirror, String name) =>
      '/data/worktrees/${mirror.githubRepoId}/$name';

  @override
  Future<GitMirror> ensureMirror({
    required int githubRepoId,
    required String remoteUrl,
  }) async {
    calls.add('ensureMirror $githubRepoId $remoteUrl');
    return GitMirror(
      githubRepoId: githubRepoId,
      path: '/mirrors/$githubRepoId.git',
    );
  }

  @override
  Future<void> fetch(GitMirror mirror) async {
    calls.add('fetch');
    final failure = fetchFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<String> resolveRef(GitMirror mirror, String ref) async {
    calls.add('resolveRef $ref');
    return refs[ref] ?? (throw GitRefNotFoundException(ref));
  }

  @override
  Future<List<GitTagInfo>> listTags(GitMirror mirror) async => [
    for (final entry in tags.entries)
      GitTagInfo(name: entry.key, commit: entry.value),
  ];

  @override
  Future<List<String>> changedFiles(
    GitMirror mirror, {
    required String from,
    required String to,
  }) => throw UnimplementedError();

  @override
  Future<GitWorktree> createWorktree(
    GitMirror mirror, {
    required String name,
    required String sha,
  }) async {
    calls.add('createWorktree $name $sha');
    onWorktree?.call(name, sha);
    return GitWorktree(
      mirror: mirror,
      path: worktreePath ?? pathOf(mirror, name),
      sha: sha,
    );
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
  }) => throw UnimplementedError();

  @override
  Future<void> removeWorktree(GitWorktree worktree) async {
    calls.add('removeWorktree ${worktree.path}');
  }

  @override
  Future<TagOutcome> createTag(
    GitMirror mirror, {
    required String name,
    required String sha,
    required String message,
  }) async {
    calls.add('createTag $name $sha');
    final existing = tags[name];
    if (existing == null) {
      tags[name] = sha;
      return TagOutcome.created;
    }
    if (existing != sha) {
      throw GitTagConflictException(
        tag: name,
        existingSha: existing,
        requestedSha: sha,
      );
    }
    return TagOutcome.reused;
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
    if (current != null) {
      throw GitBranchConflictException(
        branch: name,
        currentSha: current,
        requestedSha: sha,
      );
    }
    branches[name] = sha;
    return BranchOutcome.created;
  }

  @override
  Future<void> push(GitMirror mirror, {required List<String> refspecs}) async {
    calls.add('push ${refspecs.join(' ')}');
    final failure = pushFailure;
    if (failure != null) throw failure;
    pushed.add(refspecs);
  }
}

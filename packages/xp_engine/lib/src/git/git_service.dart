import 'package:xp_engine/src/git/git_models.dart';

/// Git operations on the engine's bare mirrors (D-04, D-05, D-11).
///
/// The engine writes to a repository only through this interface, and only
/// release-model changes: version commits in a job's worktree, tags,
/// `release/*` branches and pushes. Nothing here
/// forces: a tag never moves, a branch only moves forward, a push never starts
/// with `+`. The picked folder of a project is never touched.
///
/// `xp_adapters` has the `git` CLI implementation. Every method throws a
/// `GitException` (or a subclass) when git fails.
abstract interface class GitService {
  /// The bare mirror for the GitHub repository [githubRepoId], created empty
  /// if it does not exist yet, with `origin` set to [remoteUrl].
  ///
  /// Does no network I/O; call [fetch] to fill it. Passing a different
  /// [remoteUrl] for an existing mirror updates `origin`: that is how a GitHub
  /// rename is followed (D-05).
  Future<GitMirror> ensureMirror({
    required int githubRepoId,
    required String remoteUrl,
  });

  /// Brings [mirror] up to date with `origin`: branches under
  /// `refs/remotes/origin/*` and all tags, pruning what the remote no longer
  /// has.
  Future<void> fetch(GitMirror mirror);

  /// The full SHA of the commit that [ref] names in [mirror].
  ///
  /// [ref] is a full or abbreviated SHA, a branch (a local branch wins over
  /// `origin`'s) or a tag. Throws a `GitRefNotFoundException` if there is no
  /// such commit.
  Future<String> resolveRef(GitMirror mirror, String ref);

  /// Every tag of [mirror] with the commit it names, sorted by name.
  Future<List<GitTagInfo>> listTags(GitMirror mirror);

  /// The files whose content differs between the commits [from] and [to] of
  /// [mirror] (the two refs are resolved like [resolveRef] does), as paths
  /// relative to the repository root. A renamed file is both: its old and its
  /// new path. Sorted.
  ///
  /// Throws a `GitRefNotFoundException` if either does not exist.
  Future<List<String>> changedFiles(
    GitMirror mirror, {
    required String from,
    required String to,
  });

  /// Checks out the commit [sha] of [mirror] in a fresh directory for [name],
  /// typically a job id. The head is detached.
  ///
  /// A leftover directory of the same [name] is replaced. Throws a
  /// `GitRefNotFoundException` if [sha] is not in the mirror.
  Future<GitWorktree> createWorktree(
    GitMirror mirror, {
    required String name,
    required String sha,
  });

  /// What differs between [worktree] and the commit it has checked out.
  Future<GitWorktreeStatus> status(GitWorktree worktree);

  /// Commits the current content of [paths] (relative to the worktree) to the
  /// head of [worktree], with [message], as the engine's identity.
  ///
  /// If [paths] already are as the head has them, nothing is committed and the
  /// result says so: a version bump that ran before is not repeated (D-18).
  /// Other changes in the worktree stay out of the commit. The head of the
  /// worktree moves to the new commit; it stays detached. Throws an
  /// `ArgumentError` for an empty list, a blank message or a path that is
  /// absolute, starts with `-` or climbs with `..`.
  Future<GitCommitResult> commit(
    GitWorktree worktree, {
    required String message,
    required List<String> paths,
  });

  /// Deletes [worktree] and its directory. Does nothing if it is gone.
  Future<void> removeWorktree(GitWorktree worktree);

  /// Tags the commit [sha] of [mirror] as [name] with an annotated tag that
  /// carries [message].
  ///
  /// An existing tag on the same commit is reused ([TagOutcome.reused]); one on
  /// another commit throws a `GitTagConflictException`. Annotated tags carry
  /// the tagger and date, and are what `git describe` and release listings
  /// prefer.
  Future<TagOutcome> createTag(
    GitMirror mirror, {
    required String name,
    required String sha,
    required String message,
  });

  /// Creates the local branch [name] on [sha], or moves it forward to [sha].
  ///
  /// Throws a `GitBranchConflictException` if the branch exists and [sha] is
  /// not a descendant of its tip. Never forces. The branch reaches the remote
  /// with [push].
  Future<BranchOutcome> upsertBranch(
    GitMirror mirror, {
    required String name,
    required String sha,
  });

  /// Pushes [refspecs] (see `GitRefspecs`) to `origin`.
  ///
  /// Throws an `ArgumentError` for a refspec that is not `refs/...:refs/...`
  /// or that starts with `+`, and a `GitPushRejectedException` when the remote
  /// refuses, for example because the push is not a fast-forward.
  Future<void> push(GitMirror mirror, {required List<String> refspecs});
}

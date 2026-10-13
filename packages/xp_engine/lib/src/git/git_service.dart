import 'package:xp_engine/src/git/git_models.dart';

/// Git operations on the engine's bare mirrors (D-04, D-05, D-11).
///
/// The engine writes to a repository only through this interface, and only
/// release-model changes: tags, `release/*` branches and pushes. Nothing here
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

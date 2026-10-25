import 'package:equatable/equatable.dart';

/// The engine's bare repository for one project (D-05, ADR 0015).
class GitMirror extends Equatable {
  /// Creates a mirror record.
  const new({required this.key, required this.path});

  /// What a mirror key looks like: a GitHub repository id in decimal, or `h`
  /// and 16 hex digits for a repository on another host.
  static final keyPattern = RegExp(r'^(\d+|h[0-9a-f]{16})$');

  /// The project's source key. A GitHub repository id survives renames, so
  /// it keys the mirror of a GitHub project.
  final String key;

  /// The directory of the bare repository.
  final String path;

  @override
  List<Object?> get props => [key, path];
}

/// A checkout of one commit for one job, apart from the mirror and from every
/// other worktree.
class GitWorktree extends Equatable {
  /// Creates a worktree record.
  const new({required this.mirror, required this.path, required this.sha});

  /// The mirror the worktree belongs to.
  final GitMirror mirror;

  /// The directory that holds the checkout. The head is detached.
  final String path;

  /// The full SHA of the checked out commit.
  final String sha;

  @override
  List<Object?> get props => [mirror, path, sha];
}

/// A commit of a mirror: its id, subject and the rest of its message.
class GitCommit extends Equatable {
  /// Creates a commit.
  const new({required this.sha, required this.subject, this.body = ''});

  /// The commit, in full.
  final String sha;

  /// The first line of the message.
  final String subject;

  /// The message after the subject, without the blank line between them.
  final String body;

  @override
  List<Object?> get props => [sha, subject, body];
}

/// A tag of a mirror and the commit it names.
class GitTagInfo extends Equatable {
  /// Creates a tag record.
  const new({required this.name, required this.commit});

  /// The tag name, for example `v1.2.3+45`.
  final String name;

  /// The full SHA of the commit the tag names. An annotated tag is followed
  /// to its commit.
  final String commit;

  @override
  List<Object?> get props => [name, commit];
}

/// What `git status` says about a worktree.
class GitWorktreeStatus extends Equatable {
  /// Creates a status.
  const new({
    required this.headSha,
    this.changed = const [],
    this.untracked = const [],
  });

  /// The full SHA of the checked out commit.
  final String headSha;

  /// Tracked files that differ from the commit, staged or not, deleted or
  /// not. Paths are relative to the worktree, separated by `/`.
  final List<String> changed;

  /// Files that are neither tracked nor ignored, one entry per file.
  final List<String> untracked;

  /// Whether the worktree is exactly the commit.
  bool get isClean => changed.isEmpty && untracked.isEmpty;

  @override
  List<Object?> get props => [headSha, changed, untracked];
}

/// What `GitService.commit` did.
class GitCommitResult extends Equatable {
  /// Creates a result.
  const new({required this.sha, required this.tree, required this.created});

  /// The full SHA of the head after the call: the new commit, or the old
  /// head if there was nothing to commit.
  final String sha;

  /// The tree of [sha]. Two commits with the same tree hold the same files.
  final String tree;

  /// Whether a commit was made. `false` means the files already were as
  /// asked, so there was nothing to commit (idempotent, D-18).
  final bool created;

  @override
  List<Object?> get props => [sha, tree, created];
}

/// What `GitService.createTag` did.
enum TagOutcome {
  /// The tag did not exist and was created.
  created,

  /// The tag already existed on the same commit and was left alone (D-11).
  reused,
}

/// What `GitService.upsertBranch` did.
enum BranchOutcome {
  /// The branch did not exist and was created.
  created,

  /// The branch moved forward to a descendant commit.
  updated,

  /// The branch was already on the commit.
  unchanged,
}

/// Builds the refspecs for `GitService.push`.
///
/// A refspec is always `src:dst` with the same full ref on both sides and never
/// starts with `+`, so a push can only create a ref or fast-forward it.
abstract final class GitRefspecs {
  /// The refspec that pushes the local branch [name].
  static String branch(String name) => 'refs/heads/$name:refs/heads/$name';

  /// The refspec that pushes the tag [name].
  static String tag(String name) => 'refs/tags/$name:refs/tags/$name';
}

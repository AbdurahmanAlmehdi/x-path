import 'package:equatable/equatable.dart';

/// The engine's bare repository for one GitHub repository (D-05).
class GitMirror extends Equatable {
  /// Creates a mirror record.
  const new({required this.githubRepoId, required this.path});

  /// The id GitHub gave the repository. It survives renames, so it keys the
  /// mirror.
  final int githubRepoId;

  /// The directory of the bare repository.
  final String path;

  @override
  List<Object?> get props => [githubRepoId, path];
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

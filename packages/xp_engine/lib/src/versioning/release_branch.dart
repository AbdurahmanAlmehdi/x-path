import 'package:xp_engine/src/git/git_models.dart';
import 'package:xp_engine/src/git/git_service.dart';
import 'package:xp_engine/src/versioning/app_version.dart';
import 'package:xp_engine/src/versioning/release_model.dart';

/// What `ReleaseBranchCutter.cut` did.
class ReleaseBranchCut {
  /// Creates the record.
  const new({required this.name, required this.outcome});

  /// The release branch, for example `release/5.4.1`.
  final String name;

  /// Whether the branch was created, moved forward or already was there.
  final BranchOutcome outcome;
}

/// Cuts the release line of a version (docs/RELEASING.md): `release/<x.y.z>`
/// at the commit the release is dispatched from.
///
/// The branch names the line, not the latest version on it, so a native
/// hotfix of `5.4.2` goes onto the branch `release/5.4.1` already there.
class ReleaseBranchCutter {
  /// Creates a cutter.
  const new(this._git);

  final GitService _git;

  /// Creates the release branch of [version] on [sha] in [mirror].
  ///
  /// A branch that already is on [sha] is left alone (D-18: running again
  /// changes nothing) and one that is behind it moves forward. The branch
  /// reaches the remote with `GitService.push`.
  ///
  /// Throws a `GitBranchConflictException` if the branch exists on a commit
  /// that [sha] does not descend from: XPath never forces (D-11).
  Future<ReleaseBranchCut> cut(
    GitMirror mirror, {
    required VersionName version,
    required String sha,
    ReleaseModel model = const ReleaseModel(),
    TagScope scope = const TagScope(),
  }) async {
    final name = model.branchName(version, scope: scope);
    final outcome = await _git.upsertBranch(mirror, name: name, sha: sha);
    return ReleaseBranchCut(name: name, outcome: outcome);
  }
}

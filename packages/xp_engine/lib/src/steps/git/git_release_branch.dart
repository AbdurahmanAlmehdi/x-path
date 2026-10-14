import 'package:equatable/equatable.dart';
import 'package:xp_engine/src/git/git_exceptions.dart';
import 'package:xp_engine/src/git/git_models.dart';
import 'package:xp_engine/src/git/git_service.dart';
import 'package:xp_engine/src/json_fields.dart';
import 'package:xp_engine/src/steps/step.dart';
import 'package:xp_engine/src/steps/step_context.dart';
import 'package:xp_engine/src/versioning/app_version.dart';
import 'package:xp_engine/src/versioning/release_branch.dart';
import 'package:xp_engine/src/versioning/release_worktree.dart';

/// Which release branch to cut.
class GitReleaseBranchInput extends Equatable {
  /// Creates the input.
  const new({required this.worktree, required this.version});

  /// Reads the input from its stored form.
  ///
  /// Throws a [FormatException] if a field is missing or of the wrong type,
  /// or `version` is not `x.y.z`.
  factory fromJson(Map<String, dynamic> json) => GitReleaseBranchInput(
    worktree: ReleaseWorktree.fromJson(requiredObject(json, 'worktree')),
    version: VersionName.parse(requiredString(json, 'version')),
  );

  /// The worktree whose head the branch is cut at.
  final ReleaseWorktree worktree;

  /// The version the branch is for: `release/1.2.0`.
  final VersionName version;

  /// The stored form.
  Map<String, dynamic> toJson() => {
    'worktree': worktree.toJson(),
    'version': '$version',
  };

  @override
  List<Object?> get props => [worktree, version];
}

/// What `git.releaseBranch` did.
class GitReleaseBranchResult extends Equatable {
  /// Creates the result.
  const new({required this.name, required this.outcome});

  /// The branch.
  final String name;

  /// Whether it was made, moved forward or already there.
  final BranchOutcome outcome;

  @override
  List<Object?> get props => [name, outcome];
}

/// Cuts the release branch of a version at the head of the job's worktree
/// (`git.releaseBranch`, R:227-330).
///
/// The branch only ever moves forward (D-04); a head that is not a descendant
/// of the branch fails the step. The branch reaches the remote with
/// `git.push`.
class GitReleaseBranchStep
    extends Step<GitReleaseBranchInput, GitReleaseBranchResult> {
  /// Creates the step.
  const new(this._git);

  final GitService _git;

  @override
  String get kind => 'git.releaseBranch';

  @override
  bool sideEffectOf(GitReleaseBranchInput input) => true;

  @override
  GitReleaseBranchInput decodeInput(Map<String, dynamic> json) =>
      GitReleaseBranchInput.fromJson(json);

  @override
  Map<String, dynamic> encodeInput(GitReleaseBranchInput input) =>
      input.toJson();

  @override
  Map<String, dynamic> encodeResult(GitReleaseBranchResult result) => {
    'name': result.name,
    'outcome': result.outcome.name,
  };

  @override
  Future<StepOutcome<GitReleaseBranchResult>> run(
    GitReleaseBranchInput input,
    StepContext context,
  ) async {
    final target = input.worktree;
    final head = (await _git.status(target.gitWorktree)).headSha;
    try {
      final cut = await ReleaseBranchCutter(_git).cut(
        target.mirror,
        version: input.version,
        sha: head,
        model: target.releaseModel,
        scope: target.scope,
      );
      return StepSucceeded(
        GitReleaseBranchResult(name: cut.name, outcome: cut.outcome),
      );
    } on GitBranchConflictException catch (error) {
      return StepFailed(error.message);
    }
  }
}

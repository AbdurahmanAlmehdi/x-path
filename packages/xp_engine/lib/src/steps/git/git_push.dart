import 'package:equatable/equatable.dart';
import 'package:xp_engine/src/git/git_exceptions.dart';
import 'package:xp_engine/src/git/git_models.dart';
import 'package:xp_engine/src/git/git_service.dart';
import 'package:xp_engine/src/json_fields.dart';
import 'package:xp_engine/src/steps/step.dart';
import 'package:xp_engine/src/steps/step_context.dart';
import 'package:xp_engine/src/versioning/release_worktree.dart';

/// What to push.
class GitPushInput extends Equatable {
  /// Creates the input.
  const new({required this.worktree, this.branch, this.tag})
    : assert(branch != null || tag != null, 'Push a branch or a tag.');

  /// Reads the input from its stored form.
  ///
  /// Throws a [FormatException] if a field is missing or of the wrong type,
  /// or there is neither a branch nor a tag.
  factory fromJson(Map<String, dynamic> json) {
    final branch = optionalString(json, 'branch');
    final tag = optionalString(json, 'tag');
    if (branch == null && tag == null) {
      throw const FormatException('Push a "branch" or a "tag".');
    }
    return GitPushInput(
      worktree: ReleaseWorktree.fromJson(requiredObject(json, 'worktree')),
      branch: branch,
      tag: tag,
    );
  }

  /// The worktree whose mirror is pushed from.
  final ReleaseWorktree worktree;

  /// The local branch to push.
  final String? branch;

  /// The tag to push.
  final String? tag;

  /// The refspecs: each ref to itself, never forced (D-04).
  List<String> get refspecs => [
    if (branch != null) GitRefspecs.branch(branch!),
    if (tag != null) GitRefspecs.tag(tag!),
  ];

  /// The stored form.
  Map<String, dynamic> toJson() => {
    'worktree': worktree.toJson(),
    'branch': ?branch,
    'tag': ?tag,
  };

  @override
  List<Object?> get props => [worktree, branch, tag];
}

/// What `git.push` pushed.
class GitPushResult extends Equatable {
  /// Creates the result.
  const new(this.refspecs);

  /// The refspecs that were pushed.
  final List<String> refspecs;

  @override
  List<Object?> get props => [refspecs];
}

/// Pushes the release branch and the tag to `origin` (`git.push`, R:227-330).
///
/// A push never starts with `+`: it creates a ref or fast-forwards it, and the
/// remote's refusal fails the step. Pushing is a gated action (D-13); the
/// workflow puts `gate: push` in front of it.
class GitPushStep extends Step<GitPushInput, GitPushResult> {
  /// Creates the step.
  const new(this._git);

  final GitService _git;

  @override
  String get kind => 'git.push';

  @override
  bool sideEffectOf(GitPushInput input) => true;

  @override
  GitPushInput decodeInput(Map<String, dynamic> json) =>
      GitPushInput.fromJson(json);

  @override
  Map<String, dynamic> encodeInput(GitPushInput input) => input.toJson();

  @override
  Map<String, dynamic> encodeResult(GitPushResult result) => {
    'refspecs': result.refspecs,
  };

  @override
  Future<StepOutcome<GitPushResult>> run(
    GitPushInput input,
    StepContext context,
  ) async {
    try {
      await _git.push(input.worktree.mirror, refspecs: input.refspecs);
      return StepSucceeded(GitPushResult(input.refspecs));
    } on GitPushRejectedException catch (error) {
      return StepFailed(error.message);
    }
  }
}

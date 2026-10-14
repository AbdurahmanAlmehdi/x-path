import 'package:equatable/equatable.dart';
import 'package:xp_engine/src/git/git_exceptions.dart';
import 'package:xp_engine/src/git/git_models.dart';
import 'package:xp_engine/src/git/git_service.dart';
import 'package:xp_engine/src/json_fields.dart';
import 'package:xp_engine/src/steps/step.dart';
import 'package:xp_engine/src/steps/step_context.dart';
import 'package:xp_engine/src/versioning/release_worktree.dart';

/// Which tag to make.
class GitTagInput extends Equatable {
  /// Creates the input.
  const new({
    required this.worktree,
    required this.name,
    required this.message,
  });

  /// Reads the input from its stored form.
  ///
  /// Throws a [FormatException] if a field is missing or of the wrong type.
  factory fromJson(Map<String, dynamic> json) => GitTagInput(
    worktree: ReleaseWorktree.fromJson(requiredObject(json, 'worktree')),
    name: requiredString(json, 'name'),
    message: requiredString(json, 'message'),
  );

  /// The worktree whose head is tagged.
  final ReleaseWorktree worktree;

  /// The tag, from the release model: `v1.2.0+45`.
  final String name;

  /// The message of the annotated tag.
  final String message;

  /// The stored form.
  Map<String, dynamic> toJson() => {
    'worktree': worktree.toJson(),
    'name': name,
    'message': message,
  };

  @override
  List<Object?> get props => [worktree, name, message];
}

/// What `git.tag` did.
class GitTagResult extends Equatable {
  /// Creates the result.
  const new({required this.name, required this.sha, required this.reused});

  /// The tag.
  final String name;

  /// The commit it names.
  final String sha;

  /// Whether the tag existed on that commit already (D-11).
  final bool reused;

  @override
  List<Object?> get props => [name, sha, reused];
}

/// Tags the head of the job's worktree (`git.tag`, R:227-330).
///
/// The head is the commit that was built: the version commit, or the
/// dispatched commit for a patch. A tag that exists on that commit is reused;
/// one on another commit fails the step (D-11, never forced). The tag reaches
/// the remote with `git.push`.
class GitTagStep extends Step<GitTagInput, GitTagResult> {
  /// Creates the step.
  const new(this._git);

  final GitService _git;

  @override
  String get kind => 'git.tag';

  @override
  bool sideEffectOf(GitTagInput input) => true;

  @override
  GitTagInput decodeInput(Map<String, dynamic> json) =>
      GitTagInput.fromJson(json);

  @override
  Map<String, dynamic> encodeInput(GitTagInput input) => input.toJson();

  @override
  Map<String, dynamic> encodeResult(GitTagResult result) => {
    'name': result.name,
    'sha': result.sha,
    'reused': result.reused,
  };

  /// Done when the tag names the head already.
  @override
  Future<GitTagResult?> alreadyDone(
    GitTagInput input,
    StepContext context,
  ) async {
    final head = (await _git.status(input.worktree.gitWorktree)).headSha;
    final tags = await _git.listTags(input.worktree.mirror);
    final exists = tags.any(
      (tag) => tag.name == input.name && tag.commit == head,
    );
    return exists
        ? GitTagResult(name: input.name, sha: head, reused: true)
        : null;
  }

  @override
  Future<StepOutcome<GitTagResult>> run(
    GitTagInput input,
    StepContext context,
  ) async {
    final head = (await _git.status(input.worktree.gitWorktree)).headSha;
    try {
      final outcome = await _git.createTag(
        input.worktree.mirror,
        name: input.name,
        sha: head,
        message: input.message,
      );
      return StepSucceeded(
        GitTagResult(
          name: input.name,
          sha: head,
          reused: outcome == TagOutcome.reused,
        ),
      );
    } on GitTagConflictException catch (error) {
      return StepFailed(error.message);
    }
  }
}

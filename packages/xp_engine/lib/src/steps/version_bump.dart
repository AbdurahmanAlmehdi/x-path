import 'package:equatable/equatable.dart';
import 'package:xp_engine/src/git/git_service.dart';
import 'package:xp_engine/src/json_fields.dart';
import 'package:xp_engine/src/steps/step.dart';
import 'package:xp_engine/src/steps/step_context.dart';
import 'package:xp_engine/src/versioning/app_version.dart';
import 'package:xp_engine/src/versioning/release_worktree.dart';
import 'package:xp_engine/src/versioning/version_files.dart';
import 'package:xp_engine/src/versioning/versioning_exceptions.dart';
import 'package:xp_engine/src/versioning/workspace.dart';

/// The version to write, and where.
class VersionBumpInput extends Equatable {
  /// Creates the input.
  const new({required this.worktree, required this.version});

  /// Reads the input from its stored form.
  ///
  /// Throws a [FormatException] if a field is missing or of the wrong type,
  /// or `version` is not `x.y.z+build`.
  factory fromJson(Map<String, dynamic> json) {
    final version = AppVersion.parse(requiredString(json, 'version'));
    if (version.build == null) {
      throw const FormatException('"version" needs a build number.');
    }
    return VersionBumpInput(
      worktree: ReleaseWorktree.fromJson(requiredObject(json, 'worktree')),
      version: version,
    );
  }

  /// The worktree of the job and the app in it.
  final ReleaseWorktree worktree;

  /// The version to write. The build number comes from the build counter,
  /// allocated when the release was dispatched (D-11).
  final AppVersion version;

  /// The stored form.
  Map<String, dynamic> toJson() => {
    'worktree': worktree.toJson(),
    'version': '$version',
  };

  @override
  List<Object?> get props => [worktree, version];
}

/// What `version.bump` did.
class VersionBumpResult extends Equatable {
  /// Creates the result.
  const new({required this.commit, required this.created, this.previous});

  /// The commit the worktree is on now: the version commit, or the head that
  /// already had the version.
  final String commit;

  /// Whether this run made the commit.
  final bool created;

  /// The version the pubspec had before, when this run changed it.
  final AppVersion? previous;

  @override
  List<Object?> get props => [commit, created, previous];
}

/// Writes `x.y.z+build` into the pubspec and the plists with literal versions
/// and commits them in the job's worktree (`version.bump`, R:70-88,
/// R:336-362).
///
/// The commit is a release-model git change (D-04). It reaches the remote
/// with the push step; nothing is pushed here. A version that is tagged
/// already is refused.
class VersionBumpStep extends Step<VersionBumpInput, VersionBumpResult> {
  /// Creates the step.
  const new({required this._git, required this._workspaces});

  final GitService _git;
  final WorkspaceOpener _workspaces;

  @override
  String get kind => 'version.bump';

  @override
  bool sideEffectOf(VersionBumpInput input) => true;

  @override
  VersionBumpInput decodeInput(Map<String, dynamic> json) =>
      VersionBumpInput.fromJson(json);

  @override
  Map<String, dynamic> encodeInput(VersionBumpInput input) => input.toJson();

  @override
  Map<String, dynamic> encodeResult(VersionBumpResult result) => {
    'commit': result.commit,
    'created': result.created,
    if (result.previous != null) 'previous': '${result.previous}',
  };

  /// Done when the head already holds the version in every version file and
  /// the worktree has no unfinished edit of them: the commit with this tree
  /// exists.
  @override
  Future<VersionBumpResult?> alreadyDone(
    VersionBumpInput input,
    StepContext context,
  ) async {
    final target = input.worktree;
    final paths = target.versionFilePaths;
    final VersionFilesState state;
    try {
      state = await VersionFiles(_workspaces(target.path)).read(paths);
    } on VersionFileException {
      return null;
    }
    if (!state.matches(input.version)) return null;
    final status = await _git.status(target.gitWorktree);
    if (status.changed.any(paths.contains)) return null;
    return VersionBumpResult(commit: status.headSha, created: false);
  }

  @override
  Future<StepOutcome<VersionBumpResult>> run(
    VersionBumpInput input,
    StepContext context,
  ) async {
    final target = input.worktree;
    final version = input.version;
    final paths = target.versionFilePaths;
    final tag = target.releaseModel.tagName(
      version.name,
      version.build!,
      scope: target.scope,
    );
    if ((await _git.listTags(target.mirror)).any((info) => info.name == tag)) {
      return StepFailed('$tag is already tagged.');
    }
    final files = VersionFiles(_workspaces(target.path));
    final AppVersion previous;
    try {
      previous = (await files.read(paths)).pubspec;
      await files.write(paths, version);
    } on VersionFileException catch (error) {
      return StepFailed('${error.path}: ${error.message}');
    }
    final commit = await _git.commit(
      target.gitWorktree,
      message: 'chore(release): $version',
      paths: paths,
    );
    return StepSucceeded(
      VersionBumpResult(
        commit: commit.sha,
        created: commit.created,
        previous: commit.created ? previous : null,
      ),
    );
  }
}

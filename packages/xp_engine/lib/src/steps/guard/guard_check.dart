import 'package:equatable/equatable.dart';
import 'package:xp_engine/src/git/git_service.dart';
import 'package:xp_engine/src/steps/guard/guard_input.dart';
import 'package:xp_engine/src/versioning/release_model.dart';
import 'package:xp_engine/src/versioning/version_files.dart';
import 'package:xp_engine/src/versioning/versioning_exceptions.dart';
import 'package:xp_engine/src/versioning/workspace.dart';

/// The checks a `guard` step can run, by the name a workflow gives them.
enum GuardCheckName {
  /// The source is committed, clean and free of local overrides.
  source,

  /// The App Store still takes builds for this version.
  appStoreTrain,

  /// The pubspec and the plists agree on the version.
  versionSync,

  /// A patch targets a release that exists.
  patchTarget,

  /// The version is higher than every release before it.
  newReleaseNumber,

  /// A patch changes no native file.
  patchNativeDiff,

  /// The app targets an API level Google Play accepts.
  playTargetSdk,

  /// The build number is not used already.
  buildNumberReuse,
}

/// How a check ended.
enum GuardStatus {
  /// The check found nothing wrong.
  passed,

  /// The check could not tell, or found something worth knowing. The job goes
  /// on.
  warned,

  /// The check found a problem. The job stops.
  failed,

  /// The check did not apply to this app.
  skipped,
}

/// What one check found.
class GuardCheckResult extends Equatable {
  /// Creates a result.
  const new(this.name, this.status, this.message, {this.fix});

  /// The check.
  final GuardCheckName name;

  /// How it ended.
  final GuardStatus status;

  /// What it found, for the owner. Never contains a secret.
  final String message;

  /// What the owner can do about it.
  final String? fix;

  /// The stored form.
  Map<String, dynamic> toJson() => {
    'name': name.name,
    'status': status.name,
    'message': message,
    if (fix != null) 'fix': fix,
  };

  @override
  List<Object?> get props => [name, status, message, fix];
}

/// What a check may use: the input of the step, the worktree and git.
class GuardRequest {
  /// Creates a request.
  new({required this.input, required this.workspace, required this.git});

  /// The input of the step.
  final GuardInput input;

  /// The worktree of the job.
  final Workspace workspace;

  /// Git.
  final GitService git;

  Future<VersionFilesState>? _versions;

  /// The worktree description of the input.
  ReleaseWorktree get target => input.worktree;

  /// The version as the version files say it. Read once.
  ///
  /// Throws a [VersionFileException].
  Future<VersionFilesState> versions() =>
      _versions ??= VersionFiles(workspace).read(target.versionFilePaths);

  /// The tags of the repository that belong to the release model (and app),
  /// with the commit each names.
  Future<List<({ReleaseTag tag, String commit})>> releaseTags() async => [
    for (final info in await git.listTags(target.mirror))
      if (target.releaseModel.parseTag(info.name, scope: target.scope)
          case final tag?)
        (tag: tag, commit: info.commit),
  ];
}

/// One check of a `guard` step.
///
/// A check reads facts, never changes anything, and says what it found with a
/// message and, for a problem, a fix.
abstract class GuardCheck {
  /// Creates a check.
  const new();

  /// The name a workflow gives the check.
  GuardCheckName get name;

  /// Runs the check. A version file that cannot be read is a failure of the
  /// check, not an exception.
  Future<GuardCheckResult> run(GuardRequest request) async {
    try {
      return await evaluate(request);
    } on VersionFileException catch (error) {
      return failed(
        '${error.path}: ${error.message}',
        fix:
            'Fix the version file, or the list of version files of the flavor.',
      );
    }
  }

  /// Does the check.
  Future<GuardCheckResult> evaluate(GuardRequest request);

  /// A passing result.
  GuardCheckResult passed(String message) =>
      GuardCheckResult(name, GuardStatus.passed, message);

  /// A result that lets the job go on and tells the owner something.
  GuardCheckResult warned(String message, {String? fix}) =>
      GuardCheckResult(name, GuardStatus.warned, message, fix: fix);

  /// A failing result.
  GuardCheckResult failed(String message, {String? fix}) =>
      GuardCheckResult(name, GuardStatus.failed, message, fix: fix);

  /// A result for a check that does not apply.
  GuardCheckResult skipped(String message) =>
      GuardCheckResult(name, GuardStatus.skipped, message);
}

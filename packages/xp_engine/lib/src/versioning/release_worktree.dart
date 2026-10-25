import 'package:equatable/equatable.dart';
import 'package:xp_engine/src/git/git_models.dart';
import 'package:xp_engine/src/json_fields.dart';
import 'package:xp_engine/src/scan/scan_source.dart';
import 'package:xp_engine/src/versioning/release_model.dart';

/// Where a step works: the worktree of a job, cut from the mirror at the
/// dispatched commit, and the app inside it that is being released.
///
/// It is the part of the input that the version and guard steps share. The
/// workflow engine fills it in when the job is created (Phase 11), so the
/// stored input is all a resumed job needs.
class ReleaseWorktree extends Equatable {
  /// Creates the description.
  const new({
    required this.path,
    required this.mirror,
    required this.sha,
    this.appPath = '.',
    this.versionFiles = const [],
    this.releaseModel = const ReleaseModel(),
    this.scope = const TagScope(),
  });

  /// Reads the description from its stored form.
  ///
  /// Throws a [FormatException] if a field is missing or of the wrong type,
  /// or the release model is not valid.
  factory fromJson(Map<String, dynamic> json) {
    final mirror = requiredObject(json, 'mirror');
    final scope = optionalObject(json, 'scope');
    final model = optionalObject(json, 'releaseModel');
    final key =
        mirrorKeyOf(mirror) ??
        (throw const FormatException('"mirror.key" must be a string.'));
    return ReleaseWorktree(
      path: requiredString(json, 'path'),
      mirror: GitMirror(key: key, path: requiredString(mirror, 'path')),
      sha: requiredString(json, 'sha'),
      appPath: optionalString(json, 'appPath') ?? '.',
      versionFiles: stringList(json, 'versionFiles'),
      releaseModel: model == null
          ? const ReleaseModel()
          : ReleaseModel.fromJson(model),
      scope: TagScope(
        app: optionalString(scope ?? const {}, 'app'),
        flavor: optionalString(scope ?? const {}, 'flavor'),
      ),
    );
  }

  /// The key of the stored form [mirror] of a mirror, or `null` if it has
  /// none. Jobs stored before ADR 0015 name it by its GitHub repository id.
  static String? mirrorKeyOf(Map<String, dynamic> mirror) => switch (mirror) {
    {'key': final String key} => key,
    {'githubRepoId': final int githubRepoId} => '$githubRepoId',
    _ => null,
  };

  /// The directory of the worktree.
  final String path;

  /// The mirror the worktree was cut from.
  final GitMirror mirror;

  /// The commit the release was dispatched from, in full.
  final String sha;

  /// The app directory relative to the worktree; `.` for the root.
  final String appPath;

  /// The files a version bump writes, relative to the worktree: the pubspec
  /// and every plist with a literal version. Empty means the pubspec of the
  /// app only.
  final List<String> versionFiles;

  /// The project's branch and tag names.
  final ReleaseModel releaseModel;

  /// The app and flavor that tag patterns may name.
  final TagScope scope;

  /// The worktree as git sees it. The head may be ahead of [sha] after a
  /// version commit.
  GitWorktree get gitWorktree =>
      GitWorktree(mirror: mirror, path: path, sha: sha);

  /// [relative], a path inside the app, relative to the worktree.
  String inApp(String relative) => joinScanPath(appPath, relative);

  /// The version files, with the default filled in.
  List<String> get versionFilePaths =>
      versionFiles.isEmpty ? [inApp('pubspec.yaml')] : versionFiles;

  /// The stored form.
  Map<String, dynamic> toJson() => {
    'path': path,
    'mirror': {'key': mirror.key, 'path': mirror.path},
    'sha': sha,
    'appPath': appPath,
    'versionFiles': versionFiles,
    'releaseModel': releaseModel.toJson(),
    'scope': {
      if (scope.app != null) 'app': scope.app,
      if (scope.flavor != null) 'flavor': scope.flavor,
    },
  };

  @override
  List<Object?> get props => [
    path,
    mirror,
    sha,
    appPath,
    versionFiles,
    releaseModel,
    scope,
  ];
}

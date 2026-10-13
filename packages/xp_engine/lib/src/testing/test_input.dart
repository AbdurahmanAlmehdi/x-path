import 'package:equatable/equatable.dart';
import 'package:xp_engine/src/json_fields.dart';
import 'package:xp_engine/src/versioning/release_worktree.dart';

/// What the `test` step runs.
///
/// The workflow engine fills it in when the job is created (Phase 11), so the
/// stored input is all a resumed job needs.
class TestInput extends Equatable {
  /// Creates the input.
  const new({
    required this.worktree,
    required this.branch,
    required this.baseBranch,
    this.flutterVersion,
    this.paths = const [],
    this.tags = const [],
  });

  /// Reads the input from its stored form.
  ///
  /// Throws a [FormatException] if a field is missing or of the wrong type,
  /// or a path leaves the app or a tag looks like a flag.
  factory fromJson(Map<String, dynamic> json) {
    final paths = stringList(json, 'paths');
    for (final path in paths) {
      if (path.isEmpty ||
          path.startsWith('/') ||
          path.startsWith('-') ||
          path.split('/').contains('..')) {
        throw const FormatException('"paths" must be paths inside the app.');
      }
    }
    final tags = stringList(json, 'tags');
    if (tags.any((tag) => tag.isEmpty || tag.startsWith('-'))) {
      throw const FormatException('"tags" must be tag expressions.');
    }
    return TestInput(
      worktree: ReleaseWorktree.fromJson(requiredObject(json, 'worktree')),
      branch: requiredString(json, 'branch'),
      baseBranch: requiredString(json, 'baseBranch'),
      flutterVersion: optionalString(json, 'flutterVersion'),
      paths: paths,
      tags: tags,
    );
  }

  /// The worktree of the job and the app in it.
  final ReleaseWorktree worktree;

  /// The branch under test.
  final String branch;

  /// The project's base branch, whose last green run is the baseline.
  final String baseBranch;

  /// The Flutter version the app pins in `.fvmrc`, as the scan read it.
  final String? flutterVersion;

  /// Test files or folders to run, relative to the app. Empty runs `test/`.
  final List<String> paths;

  /// Tag expressions (boolean selectors, as `--tags` takes them) that a test
  /// must all match. Flutter takes one `--tags`, so they are joined with
  /// `&&`.
  final List<String> tags;

  /// The app's directory.
  String get appDirectory => worktree.appPath == '.'
      ? worktree.path
      : '${worktree.path}/${worktree.appPath}';

  /// Whether the run is limited to some files or tags, so that it cannot be
  /// a baseline.
  bool get filtered => paths.isNotEmpty || tags.isNotEmpty;

  /// The stored form.
  Map<String, dynamic> toJson() => {
    'worktree': worktree.toJson(),
    'branch': branch,
    'baseBranch': baseBranch,
    'flutterVersion': ?flutterVersion,
    'paths': paths,
    'tags': tags,
  };

  @override
  List<Object?> get props => [
    worktree,
    branch,
    baseBranch,
    flutterVersion,
    paths,
    tags,
  ];
}

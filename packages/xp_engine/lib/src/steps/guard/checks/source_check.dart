import 'package:xp_engine/src/scan/scan_source.dart';
import 'package:xp_engine/src/steps/guard/guard_check.dart';

/// A release must be reproducible from git alone: the dispatched commit,
/// nothing uncommitted or untracked among the build inputs, and no
/// dependency taken from a local checkout (`guard_prod_source`, R:121-147).
class SourceCheck extends GuardCheck {
  /// Creates the check.
  const new();

  /// The folders and files of an app that end up in the build. An untracked
  /// file among them is compiled in without being in git.
  static const buildInputs = [
    'lib',
    'assets',
    'ios',
    'android',
    'pubspec.yaml',
  ];

  static final _pathDependency = RegExp(r'^\s+source: path$', multiLine: true);

  @override
  GuardCheckName get name => GuardCheckName.source;

  @override
  Future<GuardCheckResult> evaluate(GuardRequest request) async {
    final target = request.target;
    final status = await request.git.status(target.gitWorktree);
    final problems = <String>[
      if (status.headSha != target.sha)
        'HEAD is ${status.headSha}, not the dispatched commit ${target.sha}.',
      for (final path in status.changed) 'Uncommitted change: $path',
      for (final path in status.untracked)
        if (_isBuildInput(target.appPath, path)) 'Untracked file: $path',
    ];
    // The app's folder, and the repository root for workspaces and monorepos.
    for (final directory in {normalizeScanPath(target.appPath), ''}) {
      final overrides = joinScanPath(directory, 'pubspec_overrides.yaml');
      if (await request.workspace.exists(overrides)) {
        problems.add(
          '$overrides is active. Its dependency_overrides replace the ones '
          'in pubspec.yaml and can point at local checkouts.',
        );
      }
      final lock = joinScanPath(directory, 'pubspec.lock');
      final lockText = await request.workspace.read(lock);
      if (lockText != null && _pathDependency.hasMatch(lockText)) {
        problems.add('$lock resolves a package from a local path.');
      }
    }
    if (problems.isEmpty) {
      return passed('Source is committed and free of local overrides.');
    }
    return failed(
      problems.join('\n'),
      fix:
          'Commit or discard the changes, remove pubspec_overrides.yaml, and '
          'run pub get without local path dependencies. A release builds '
          'only what is in git.',
    );
  }

  static bool _isBuildInput(String appPath, String path) {
    for (final input in buildInputs) {
      final base = joinScanPath(appPath, input);
      if (path == base || path.startsWith('$base/')) return true;
    }
    return false;
  }
}

import 'package:xp_engine/src/scan/scan_source.dart';
import 'package:xp_engine/src/steps/guard/guard_check.dart';
import 'package:yaml/yaml.dart';

/// A release must be reproducible from git alone: the dispatched commit,
/// nothing uncommitted or untracked among the build inputs, and no
/// dependency taken from a local checkout (`guard_prod_source`, R:121-147).
///
/// A path package of `pubspec.lock` passes only if its path is relative,
/// stays inside the repository, exists in the worktree and has no
/// uncommitted or untracked file: a monorepo's own packages are in git.
class SourceCheck extends GuardCheck {
  /// Creates the check.
  const new();

  /// The folders and files of an app that end up in the build. An untracked
  /// file among them is compiled in without being in git. The folders of the
  /// app's in-repository path packages count too.
  static const buildInputs = [
    'lib',
    'assets',
    'ios',
    'android',
    'pubspec.yaml',
  ];

  @override
  GuardCheckName get name => GuardCheckName.source;

  @override
  Future<GuardCheckResult> evaluate(GuardRequest request) async {
    final target = request.target;
    final status = await request.git.status(target.gitWorktree);
    final lockProblems = <String>[];
    final packages = <_PathPackage>[];
    final notInRepo = <String>{};
    final missing = <String>{};
    var overrides = false;
    var invalidLock = false;
    // The app's folder, and the repository root for workspaces and monorepos.
    for (final directory in {normalizeScanPath(target.appPath), ''}) {
      final overridesPath = joinScanPath(directory, 'pubspec_overrides.yaml');
      if (await request.workspace.exists(overridesPath)) {
        overrides = true;
        lockProblems.add(
          '$overridesPath is active. Its dependency_overrides replace the '
          'ones in pubspec.yaml and can point at local checkouts.',
        );
      }
      final lock = joinScanPath(directory, 'pubspec.lock');
      final lockText = await request.workspace.read(lock);
      if (lockText == null) continue;
      final entries = _pathEntries(lockText);
      if (entries == null) {
        invalidLock = true;
        lockProblems.add(
          '$lock is not valid YAML, so its path packages cannot be checked.',
        );
        continue;
      }
      for (final (:name, :path, :relative) in entries) {
        final inRepo = relative && path != null && !path.startsWith('/')
            ? _within(directory, path)
            : null;
        if (path == null) {
          notInRepo.add(name);
          lockProblems.add(
            '$lock resolves the path package $name without naming its path.',
          );
        } else if (!relative || path.startsWith('/')) {
          notInRepo.add(name);
          lockProblems.add(
            '$lock resolves the path package $name from the absolute path '
            '$path.',
          );
        } else if (inRepo == null) {
          notInRepo.add(name);
          lockProblems.add(
            '$lock resolves the path package $name from $path, outside the '
            'repository.',
          );
        } else if (!await request.workspace.exists(inRepo)) {
          missing.add(name);
          lockProblems.add(
            '$lock resolves the path package $name from $inRepo, which is '
            'not in the worktree.',
          );
        } else {
          packages.add((lock: lock, name: name, folder: inRepo));
        }
      }
    }
    final untracked = [
      for (final path in status.untracked)
        if (_isBuildInput(target.appPath, path) ||
            packages.any((package) => _isUnder(package.folder, path)))
          path,
    ];
    for (final (:lock, :name, :folder) in packages) {
      if ([
        ...status.changed,
        ...untracked,
      ].any((path) => _isUnder(folder, path))) {
        lockProblems.add(
          '$lock resolves the path package $name from $folder, which has '
          'uncommitted or untracked files.',
        );
      }
    }
    final moved = status.headSha != target.sha;
    final problems = <String>[
      if (moved)
        'HEAD is ${status.headSha}, not the dispatched commit ${target.sha}.',
      for (final path in status.changed) 'Uncommitted change: $path',
      for (final path in untracked) 'Untracked file: $path',
      ...lockProblems,
    ];
    if (problems.isEmpty) {
      return passed('Source is committed and free of local overrides.');
    }
    final fixes = [
      if (moved || status.changed.isNotEmpty || untracked.isNotEmpty)
        'Commit or discard the changes.',
      if (overrides) 'Remove pubspec_overrides.yaml.',
    ];
    if (notInRepo.isNotEmpty) {
      fixes.add(
        'Take ${notInRepo.join(', ')} from git, a hosted version or a '
        'relative path inside the repository, and run pub get.',
      );
    }
    if (missing.isNotEmpty) {
      fixes.add(
        'Commit the folder of ${missing.join(', ')}, or fix its path in '
        'pubspec.yaml and run pub get.',
      );
    }
    if (invalidLock) fixes.add('Run pub get to write pubspec.lock again.');
    fixes.add('A release builds only what is in git.');
    return failed(problems.join('\n'), fix: fixes.join(' '));
  }

  /// The packages of the lock file [text] whose source is `path`, or `null`
  /// if it is not YAML.
  static List<({String name, String? path, bool relative})>? _pathEntries(
    String text,
  ) {
    final Object? document;
    try {
      document = loadYaml(text);
    } on YamlException {
      return null;
    }
    if (document case {'packages': final Map<Object?, Object?> packages}) {
      return [
        for (final MapEntry(:key, :value) in packages.entries)
          if (value
              case {'source': 'path'} && final Map<Object?, Object?> entry)
            switch (entry['description']) {
              {'path': final String path} && final description => (
                name: '$key',
                path: path,
                relative: description['relative'] == true,
              ),
              _ => (name: '$key', path: null, relative: false),
            },
      ];
    }
    return const [];
  }

  /// [path], relative to the folder [base] of the repository, as a path from
  /// the repository root; `null` if it climbs out of the repository.
  static String? _within(String base, String path) {
    final out = [...base.split('/').where((part) => part.isNotEmpty)];
    for (final part in path.split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part != '..') {
        out.add(part);
      } else if (out.isEmpty) {
        return null;
      } else {
        out.removeLast();
      }
    }
    return out.join('/');
  }

  static bool _isUnder(String folder, String path) =>
      folder.isEmpty || path == folder || path.startsWith('$folder/');

  static bool _isBuildInput(String appPath, String path) =>
      buildInputs.any((input) => _isUnder(joinScanPath(appPath, input), path));
}

typedef _PathPackage = ({String lock, String name, String folder});

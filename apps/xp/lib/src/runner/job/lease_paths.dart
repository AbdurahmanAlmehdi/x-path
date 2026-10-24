import 'package:path/path.dart' as p;
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';

/// Translates the paths in the steps of a leased job from the engine's disk to
/// the runner's.
///
/// The engine plans each step with the worktree it will make for the job:
/// `<engine data>/worktrees/<key>/<job id>`, cut from the mirror
/// `<engine data>/mirrors/<key>.git`, where the key is the project's source
/// key (ADR 0015). A runner has its own bare cache and
/// makes its own worktree (ADR 0009), so it names the same worktree and mirror
/// in its own data directory and replaces the engine's paths with them in
/// every step input. A path below the worktree (the working directory of a
/// `command` step) keeps its rest.
class LeasePaths {
  /// Creates the translation of engine paths to runner paths, [_replacements]
  /// by engine path; [worktree] is the worktree the runner makes for the job.
  const new(this._replacements, {this.worktree});

  /// Works out the translation for a job whose steps have [inputs], on a
  /// runner whose git data is in [sourceDirectory].
  ///
  /// The worktree and mirror of the job are read from the first step input
  /// that has a `worktree`. A job without one needs no translation.
  factory of(
    Iterable<Map<String, dynamic>> inputs, {
    required String sourceDirectory,
  }) {
    for (final input in inputs) {
      final worktree = input['worktree'];
      if (worktree is! Map<String, dynamic>) continue;
      final path = worktree['path'];
      final mirror = worktree['mirror'];
      if (path is! String || mirror is! Map<String, dynamic>) continue;
      final mirrorPath = mirror['path'];
      final key = ReleaseWorktree.mirrorKeyOf(mirror);
      if (mirrorPath is! String ||
          key == null ||
          !GitMirror.keyPattern.hasMatch(key)) {
        continue;
      }
      final gitMirror = GitMirror(
        key: key,
        path: mirrorLocation(sourceDirectory, key),
      );
      final worktreePath = CliGitService.worktreePath(
        sourceDirectory,
        gitMirror,
        p.basename(path),
      );
      return LeasePaths({
        path: worktreePath,
        mirrorPath: gitMirror.path,
      }, worktree: GitWorktree(mirror: gitMirror, path: worktreePath, sha: ''));
    }
    return const LeasePaths({});
  }

  /// Where the runner keeps the bare cache of the repository whose source
  /// key is [key] under [sourceDirectory].
  static String mirrorLocation(String sourceDirectory, String key) =>
      p.join(sourceDirectory, 'mirrors', '$key.git');

  final Map<String, String> _replacements;

  /// The worktree the runner makes for the job, or `null` if no step has one.
  /// Its `sha` is empty: the commit is the offer's.
  final GitWorktree? worktree;

  /// The runner's path for the engine's [path]; [path] if it is none of the
  /// translated ones.
  String path(String path) {
    for (final MapEntry(key: from, value: to) in _replacements.entries) {
      if (path == from) return to;
      if (path.startsWith('$from/')) return to + path.substring(from.length);
    }
    return path;
  }

  /// [input] with every string translated, nested ones too.
  Map<String, dynamic> input(Map<String, dynamic> input) =>
      _value(input)! as Map<String, dynamic>;

  Object? _value(Object? value) => switch (value) {
    final String text => path(text),
    final Map<dynamic, dynamic> map => {
      for (final entry in map.entries) '${entry.key}': _value(entry.value),
    },
    final List<dynamic> items => [for (final item in items) _value(item)],
    _ => value,
  };
}

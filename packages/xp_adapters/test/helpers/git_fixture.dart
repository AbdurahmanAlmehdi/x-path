import 'dart:io';

import 'package:path/path.dart' as p;

/// A bare "GitHub" origin on disk and a clone to commit from, for tests that
/// run real git. Nothing in it reads the user's git configuration.
class GitFixture {
  new _(this.root)
    : origin = p.join(root.path, 'origin.git'),
      seed = p.join(root.path, 'seed') {
    git(['init', '--bare', '--quiet', '--initial-branch=main', origin]);
    git(['clone', '--quiet', origin, seed]);
    git(['checkout', '--quiet', '-b', 'main'], cwd: seed);
  }

  /// Creates the fixture in a new temporary directory.
  new create() : this._(Directory.systemTemp.createTempSync('xp_git_fixture_'));

  /// The temporary directory that holds everything.
  final Directory root;

  /// The bare repository the engine mirrors and pushes to.
  final String origin;

  /// A clone of [origin] to make commits in.
  final String seed;

  /// The URL of the origin.
  String get originUrl => Uri.file(origin).toString();

  /// The environment of every git command here.
  static Map<String, String> get environment => {
    'GIT_CONFIG_NOSYSTEM': '1',
    'GIT_CONFIG_GLOBAL': '/dev/null',
    'GIT_TERMINAL_PROMPT': '0',
    'GIT_AUTHOR_NAME': 'Fixture',
    'GIT_AUTHOR_EMAIL': 'fixture@example.com',
    'GIT_COMMITTER_NAME': 'Fixture',
    'GIT_COMMITTER_EMAIL': 'fixture@example.com',
    'LC_ALL': 'C',
  };

  /// Runs git in [cwd] (default: the seed clone) and returns its output.
  /// Fails the test if git fails.
  String git(List<String> arguments, {String? cwd}) {
    final result = Process.runSync(
      'git',
      arguments,
      workingDirectory:
          cwd ?? (Directory(seed).existsSync() ? seed : root.path),
      environment: environment,
    );
    if (result.exitCode != 0) {
      throw StateError('git ${arguments.join(' ')} failed: ${result.stderr}');
    }
    return (result.stdout as String).trim();
  }

  /// Commits [content] to [file] on the current branch of the seed clone and
  /// returns the new commit.
  String commit(String file, String content, {String message = 'commit'}) {
    File(p.join(seed, file))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
    git(['add', '--', file]);
    git(['commit', '--quiet', '-m', message]);
    return git(['rev-parse', 'HEAD']);
  }

  /// Pushes branch [name] of the seed clone to the origin.
  void push(String name) => git(['push', '--quiet', 'origin', name]);

  /// The commit that [ref] points at in the origin, or `null`.
  String? originRef(String ref) {
    final result = Process.runSync(
      'git',
      ['rev-parse', '--verify', '--quiet', '$ref^{commit}'],
      workingDirectory: origin,
      environment: environment,
    );
    return result.exitCode == 0 ? (result.stdout as String).trim() : null;
  }

  /// Deletes everything.
  void dispose() => root.deleteSync(recursive: true);
}

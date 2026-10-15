import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';

/// Finds the GitHub CLI.
///
/// Looks for an executable file called `gh` in each directory of [path] (a
/// `PATH` value), then at each of [fallbacks], and returns the first one, or
/// `null` if there is none.
String? findGhExecutable({
  required String? path,
  required List<String> fallbacks,
}) {
  final candidates = [
    for (final directory in (path ?? '').split(':'))
      if (directory.isNotEmpty) p.join(directory, 'gh'),
    ...fallbacks,
  ];
  for (final candidate in candidates) {
    if (_isExecutableFile(candidate)) return candidate;
  }
  return null;
}

bool _isExecutableFile(String path) {
  final stat = FileStat.statSync(path);
  return stat.type == FileSystemEntityType.file && stat.mode & 0x49 != 0;
}

/// The token of the GitHub CLI of the engine machine, with `gh` looked up
/// at each read ([findGhExecutable] over [path] and [fallbacks]): the owner
/// may install it while the engine runs.
class LocatingGitHubCliToken implements GitHubCliToken {
  /// Creates the reader.
  const new({
    required this._runner,
    required this._secrets,
    required this.path,
    required this.fallbacks,
  });

  /// The `PATH` to look on.
  final String? path;

  /// Where to look when `gh` is not on [path].
  final List<String> fallbacks;

  final ProcessRunner _runner;
  final SecretStore _secrets;

  @override
  Future<String> read() async {
    final gh = findGhExecutable(path: path, fallbacks: fallbacks);
    if (gh == null) {
      throw GitHubCliTokenException(
        'The GitHub CLI (gh) was not found on the engine machine, on PATH '
        'or in ${fallbacks.join(', ')}.',
        fix:
            'Install it (brew install gh), log in with gh auth login, and '
            'try again; or paste a token instead.',
      );
    }
    return await GitHubTokenImporter(
      runner: _runner,
      secrets: _secrets,
      ghExecutable: gh,
    ).read();
  }
}

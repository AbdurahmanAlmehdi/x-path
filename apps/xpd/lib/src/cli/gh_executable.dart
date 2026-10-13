import 'dart:io';

import 'package:path/path.dart' as p;

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

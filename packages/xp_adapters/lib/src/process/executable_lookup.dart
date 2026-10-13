import 'dart:io';

import 'package:path/path.dart' as p;

/// The path of the program [name] as a shell would find it.
///
/// A [name] with a slash is a path itself. Otherwise the directories of
/// [path] (a `PATH` value) are searched in order. Returns `null` if no such
/// executable file exists.
String? findExecutable(String name, String? path) {
  if (name.isEmpty) return null;
  if (name.contains('/')) return _isExecutable(name) ? name : null;
  for (final directory in (path ?? '').split(':')) {
    if (directory.isEmpty) continue;
    final candidate = p.join(directory, name);
    if (_isExecutable(candidate)) return candidate;
  }
  return null;
}

bool _isExecutable(String path) {
  final stat = FileStat.statSync(path);
  // Any of the three execute bits.
  return stat.type == FileSystemEntityType.file && stat.mode & 0x49 != 0;
}

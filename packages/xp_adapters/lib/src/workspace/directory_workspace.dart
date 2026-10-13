import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xp_engine/xp_engine.dart';

/// A [Workspace] over a directory of the engine's machine: the worktree of a
/// job.
///
/// A path that is absolute, climbs with `..`, or resolves through a symbolic
/// link to somewhere outside the directory does not exist as far as it is
/// concerned, and cannot be written, so a repository cannot make a step touch
/// other files. A file is read strictly as UTF-8, so that a file that is not
/// text is never rewritten with replacement characters. A file larger than
/// [maxFileBytes] reads as missing.
class DirectoryWorkspace implements Workspace {
  /// Creates a workspace over the directory at [root].
  const new(this.root, {this.maxFileBytes = 16 * 1024 * 1024});

  /// The directory.
  final String root;

  /// The largest file that is read.
  final int maxFileBytes;

  @override
  Future<bool> exists(String path) async => _resolve(path) != null;

  @override
  Future<String?> read(String path) async {
    final resolved = _resolve(path);
    if (resolved == null) return null;
    final file = File(resolved);
    try {
      if (file.statSync().type != FileSystemEntityType.file ||
          file.lengthSync() > maxFileBytes) {
        return null;
      }
      return utf8.decode(file.readAsBytesSync());
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  @override
  Future<List<ScanEntry>> list(String path) async {
    final resolved = _resolve(path);
    if (resolved == null) return const [];
    try {
      return [
        for (final entity in Directory(resolved).listSync())
          ScanEntry(p.basename(entity.path), isDirectory: entity is Directory),
      ]..sort((a, b) => a.name.compareTo(b.name));
    } on FileSystemException {
      return const [];
    }
  }

  @override
  Future<void> write(String path, String content) async {
    final resolved = _resolve(path);
    if (resolved == null ||
        FileSystemEntity.typeSync(resolved) != FileSystemEntityType.file) {
      throw FileSystemException('There is no file in the workspace', path);
    }
    File(resolved).writeAsStringSync(content);
  }

  /// The real location of [path], or `null` if it does not exist or is not
  /// inside [root].
  String? _resolve(String path) {
    if (path.startsWith('/') || path.split('/').contains('..')) return null;
    try {
      final realRoot = Directory(root).resolveSymbolicLinksSync();
      final resolved = Directory(
        path.isEmpty ? realRoot : p.join(realRoot, path),
      ).resolveSymbolicLinksSync();
      return resolved == realRoot || p.isWithin(realRoot, resolved)
          ? resolved
          : null;
    } on FileSystemException {
      return null;
    }
  }
}

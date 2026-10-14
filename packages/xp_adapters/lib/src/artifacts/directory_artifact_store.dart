import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xp_engine/xp_engine.dart';

/// The artifact store as a directory: `<root>/<job id>/<file name>`, where
/// `root` is `<data-dir>/artifacts`.
///
/// A file is written under a temporary name and renamed, so a reader never
/// sees half of it.
class DirectoryArtifactStore implements LocalArtifactStore {
  /// Creates a store in the directory [root], which is created when the first
  /// file is written.
  const new(this.root);

  /// The directory.
  final String root;

  @override
  Future<void> write(String path, Stream<List<int>> content) async {
    final target = File(_resolve(path));
    target.parent.createSync(recursive: true);
    final partial = File('${target.path}.partial');
    final sink = partial.openWrite();
    try {
      await sink.addStream(content);
      await sink.close();
      partial.renameSync(target.path);
    } on Object {
      // The failure to report is the first one, not a second one from closing.
      try {
        await sink.close();
      } on Object {
        // Already closed by the failed write.
      }
      if (partial.existsSync()) partial.deleteSync();
      rethrow;
    }
  }

  @override
  String localPath(String path) => _resolve(path);

  @override
  Stream<List<int>> read(String path) => File(_resolve(path)).openRead();

  @override
  Future<bool> exists(String path) async => File(_resolve(path)).existsSync();

  @override
  Future<void> delete(String path) async {
    final file = File(_resolve(path));
    if (file.existsSync()) file.deleteSync();
    final folder = file.parent;
    if (folder.existsSync() && folder.listSync().isEmpty) folder.deleteSync();
  }

  /// The file of [path] in the directory.
  String _resolve(String path) {
    final parts = path.split('/');
    if (parts.length != 2 ||
        parts.any(
          (part) =>
              part.isEmpty ||
              part == '.' ||
              part == '..' ||
              part.contains(r'\') ||
              part.contains('\x00'),
        )) {
      throw ArgumentError.value(
        path,
        'path',
        'must be <folder>/<name> with plain names',
      );
    }
    return p.join(root, parts[0], parts[1]);
  }
}

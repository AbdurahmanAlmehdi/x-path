import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:xp_engine/xp_engine.dart';

/// The folders of a build on this machine's disk.
class DirectoryBuildDirectories implements BuildDirectories {
  /// Creates the accessor.
  const new();

  @override
  Future<bool> exists(String path) async => Directory(path).existsSync();

  @override
  Future<int> remove(String path) async {
    final directory = Directory(path);
    var bytes = 0;
    for (final entity in directory.listSync(recursive: true)) {
      if (entity is File) bytes += entity.lengthSync();
    }
    directory.deleteSync(recursive: true);
    return bytes;
  }

  /// Packs the folder into a temporary ZIP file, streams it and deletes it,
  /// so that dSYMs of hundreds of megabytes never sit in memory.
  @override
  Stream<List<int>> zip(String path) async* {
    final scratch = Directory.systemTemp.createTempSync('xpath-zip-');
    try {
      final target = '${scratch.path}/archive.zip';
      final encoder = ZipFileEncoder()..create(target);
      try {
        await encoder.addDirectory(Directory(path));
      } finally {
        await encoder.close();
      }
      yield* File(target).openRead();
    } finally {
      scratch.deleteSync(recursive: true);
    }
  }
}

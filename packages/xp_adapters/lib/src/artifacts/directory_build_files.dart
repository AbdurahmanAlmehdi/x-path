import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xp_engine/xp_engine.dart';

/// The files of a build on this machine's disk.
class DirectoryBuildFiles implements BuildFiles {
  /// Creates the accessor.
  const new();

  /// Writes a marker file to the app's `build/` folder the first time a step
  /// asks, and answers the time the file system gave it, so that the marker
  /// and the modification times of the build output come from the same clock
  /// (R:196). Later attempts of the step find the file and answer its time.
  @override
  Future<DateTime> markBuildStart(
    String appDirectory, {
    required String jobId,
    required int ordinal,
  }) async {
    final marker = File(
      p.join(appDirectory, 'build', '.xpath-build-start-$jobId-$ordinal'),
    );
    if (!marker.existsSync()) marker.createSync(recursive: true);
    return marker.statSync().modified.toUtc();
  }

  @override
  Future<BuildFile?> stat(String path) async {
    final stat = FileStat.statSync(path);
    return stat.type == FileSystemEntityType.file
        ? BuildFile(path, modified: stat.modified.toUtc())
        : null;
  }

  @override
  Future<List<BuildFile>> find(String directory, {required String name}) async {
    final root = Directory(directory);
    if (!root.existsSync()) return const [];
    return [
      for (final entity in root.listSync(recursive: true, followLinks: false))
        if (entity is File && p.basename(entity.path) == name)
          BuildFile(entity.path, modified: entity.statSync().modified.toUtc()),
    ];
  }

  @override
  Future<List<BuildFile>> list(
    String directory, {
    required String extension,
  }) async => [
    for (final file in _filesWith(directory, extension))
      BuildFile(file.path, modified: file.statSync().modified.toUtc()),
  ];

  @override
  Future<void> deleteAll(String directory, {required String extension}) async {
    _filesWith(directory, extension).forEach((file) => file.deleteSync());
  }

  @override
  Stream<List<int>> open(String path) => File(path).openRead();

  Iterable<File> _filesWith(String directory, String extension) {
    final root = Directory(directory);
    if (!root.existsSync()) return const [];
    return root.listSync().whereType<File>().where(
      (file) => file.path.endsWith(extension),
    );
  }
}

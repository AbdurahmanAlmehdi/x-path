import 'package:xp_engine/xp_engine.dart';

/// The files of a build, in memory, with the times they were written.
class FakeBuildFiles implements BuildFiles {
  /// The time [markBuildStart] answers.
  DateTime markedAt = DateTime.utc(2026, 10, 13, 9);

  /// Bytes and modification time by path.
  final files = <String, (List<int>, DateTime)>{};

  /// Every path [deleteAll] removed.
  final deleted = <String>[];

  /// Puts a file there, written [modified] (after the marker by default).
  void put(String path, {DateTime? modified, List<int> bytes = const [1, 2]}) =>
      files[path] = (
        bytes,
        modified ?? markedAt.add(const Duration(minutes: 1)),
      );

  @override
  Future<DateTime> markBuildStart() async => markedAt;

  @override
  Future<BuildFile?> stat(String path) async {
    final file = files[path];
    return file == null ? null : BuildFile(path, modified: file.$2);
  }

  @override
  Future<List<BuildFile>> find(
    String directory, {
    required String name,
  }) async => [
    for (final entry in files.entries)
      if (entry.key.startsWith('$directory/') && entry.key.endsWith('/$name'))
        BuildFile(entry.key, modified: entry.value.$2),
  ];

  @override
  Future<List<BuildFile>> list(
    String directory, {
    required String extension,
  }) async => [
    for (final entry in files.entries)
      if (entry.key.startsWith('$directory/') &&
          !entry.key.substring(directory.length + 1).contains('/') &&
          entry.key.endsWith(extension))
        BuildFile(entry.key, modified: entry.value.$2),
  ];

  @override
  Future<void> deleteAll(String directory, {required String extension}) async {
    final doomed = [
      for (final file in await list(directory, extension: extension)) file.path,
    ];
    deleted.addAll(doomed);
    doomed.forEach(files.remove);
  }

  @override
  Stream<List<int>> open(String path) => Stream.value(files[path]!.$1);
}

import 'dart:io';

import 'package:xp_engine/xp_engine.dart';

/// A [ScanSource] over a real directory, for tests that scan the fixtures.
///
/// `xp_adapters` has the production implementation; the engine cannot depend
/// on it, so its tests carry this small one.
class DirectoryScanSource implements ScanSource {
  /// Creates a source over [root].
  const new(this.root);

  /// The directory.
  final Directory root;

  @override
  Future<bool> exists(String path) async =>
      FileSystemEntity.typeSync(_resolve(path)) !=
      FileSystemEntityType.notFound;

  @override
  Future<String?> read(String path) async {
    final file = File(_resolve(path));
    return file.existsSync() ? file.readAsStringSync() : null;
  }

  @override
  Future<List<ScanEntry>> list(String path) async {
    final directory = Directory(_resolve(path));
    if (!directory.existsSync()) return const [];
    return [
      for (final entity in directory.listSync())
        ScanEntry(
          entity.uri.pathSegments.where((s) => s.isNotEmpty).last,
          isDirectory: entity is Directory,
        ),
    ]..sort((a, b) => a.name.compareTo(b.name));
  }

  String _resolve(String path) =>
      path.isEmpty ? root.path : '${root.path}/$path';
}

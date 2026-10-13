import 'package:xp_engine/xp_engine.dart';

/// The folders of a build, in memory: each is a path with the size of what it
/// holds.
class FakeBuildDirectories implements BuildDirectories {
  /// The folders and the bytes in them.
  final folders = <String, int>{};

  /// Every folder [remove] deleted, oldest first.
  final removed = <String>[];

  /// The bytes [zip] answers for a folder.
  List<int> zipped = const [80, 75, 3, 4];

  /// Every folder [zip] was asked for.
  final zips = <String>[];

  @override
  Future<bool> exists(String path) async => folders.containsKey(path);

  @override
  Future<int> remove(String path) async {
    removed.add(path);
    return folders.remove(path)!;
  }

  @override
  Stream<List<int>> zip(String path) {
    zips.add(path);
    return Stream.value(zipped);
  }
}

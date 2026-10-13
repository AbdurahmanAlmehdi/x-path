/// The folders a build leaves, and what steps do with whole folders: look for
/// them, remove them, pack them.
///
/// `xp_adapters` has the `dart:io` implementation. Paths are absolute.
abstract interface class BuildDirectories {
  /// Whether there is a folder at [path].
  Future<bool> exists(String path);

  /// Deletes the folder at [path] with everything in it and returns how many
  /// bytes its files held.
  Future<int> remove(String path);

  /// A ZIP archive of the folder at [path]. Its entries are named after the
  /// folder and the files in it (`dSYMs/Runner.app.dSYM/...`), so that
  /// unpacking it restores the folder.
  ///
  /// The stream fails if there is no such folder; check [exists] first.
  Stream<List<int>> zip(String path);
}

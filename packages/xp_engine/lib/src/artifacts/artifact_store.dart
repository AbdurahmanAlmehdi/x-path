import 'dart:async';

/// The files of the artifact store, by path: `<jobId>/<name>`.
///
/// The store only keeps bytes; the records, sizes and checksums are the
/// `ArtifactRepository`'s. `xp_adapters` has the directory implementation,
/// `<data-dir>/artifacts`.
abstract interface class ArtifactStore {
  /// Writes [content] to [path], replacing the file that is there. A reader
  /// never sees a half-written file.
  ///
  /// Throws an [ArgumentError] if [path] is not `<folder>/<name>` with plain
  /// names (no `..`, no empty or absolute part).
  Future<void> write(String path, Stream<List<int>> content);

  /// The bytes of the file at [path]. Check [exists] first: the stream fails
  /// if there is no such file.
  Stream<List<int>> read(String path);

  /// Whether there is a file at [path].
  Future<bool> exists(String path);
}

/// An [ArtifactStore] whose files are ordinary files on the engine machine,
/// for programs that need a path (altool uploads an IPA from a path).
abstract interface class LocalArtifactStore implements ArtifactStore {
  /// The absolute path of the file at [path] in the store.
  ///
  /// Throws an [ArgumentError] like [write] if [path] is not
  /// `<folder>/<name>`. The file may not exist; check [exists].
  String localPath(String path);
}

/// An [ArtifactStore] in memory, for tests.
class InMemoryArtifactStore implements ArtifactStore {
  /// The files, by path.
  final files = <String, List<int>>{};

  @override
  Future<void> write(String path, Stream<List<int>> content) async {
    final bytes = <int>[];
    await content.forEach(bytes.addAll);
    files[path] = bytes;
  }

  @override
  Stream<List<int>> read(String path) {
    final bytes = files[path];
    return bytes == null
        ? Stream.error(StateError('There is no file $path.'))
        : Stream.value(bytes);
  }

  @override
  Future<bool> exists(String path) async => files.containsKey(path);
}

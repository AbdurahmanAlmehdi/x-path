import 'package:xp_engine/src/scan/scan_source.dart';

/// A folder that steps read and write: the worktree of a job.
///
/// It extends the read-only [ScanSource] with writing. The picked folder of a
/// project is only ever read (D-04); only a worktree the engine made for the
/// job is opened as a workspace. Paths are relative to the folder, separated
/// by `/`, and never start with `/` or contain `..`.
///
/// `xp_adapters` has the `dart:io` implementation; [InMemoryWorkspace] is for
/// tests.
abstract interface class Workspace implements ScanSource {
  /// Replaces the text of the existing file at [path] with [content].
  ///
  /// Throws if there is no such file, or if [path] leaves the folder.
  Future<void> write(String path, String content);
}

/// Opens the workspace at the directory [path] of the engine's machine.
typedef WorkspaceOpener = Workspace Function(String path);

/// A [Workspace] over a map of file paths to their contents, for tests.
class InMemoryWorkspace implements Workspace {
  /// Creates a workspace holding [files], keyed by relative path.
  new(Map<String, String> files) : files = Map.of(files);

  /// The files as they are now.
  final Map<String, String> files;

  /// Every path written, oldest first.
  final writes = <String>[];

  ScanSource get _source => InMemoryScanSource(files);

  @override
  Future<bool> exists(String path) => _source.exists(path);

  @override
  Future<String?> read(String path) => _source.read(path);

  @override
  Future<List<ScanEntry>> list(String path) => _source.list(path);

  @override
  Future<void> write(String path, String content) async {
    if (!files.containsKey(path)) {
      throw StateError('There is no file $path to write.');
    }
    files[path] = content;
    writes.add(path);
  }
}

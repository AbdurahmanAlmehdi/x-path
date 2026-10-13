import 'package:equatable/equatable.dart';

/// A file in a worktree, as a build leaves it.
class BuildFile extends Equatable {
  /// Creates a description of the file at [path].
  const new(this.path, {required this.modified});

  /// The full path.
  final String path;

  /// When the file was last written.
  final DateTime modified;

  @override
  List<Object?> get props => [path, modified];
}

/// The files a build writes and the engine reads: what is left in `build/`,
/// and when each file was written.
///
/// `xp_adapters` has the `dart:io` implementation. Paths are absolute.
abstract interface class BuildFiles {
  /// The freshness marker: the time, as the file system tells it, at which the
  /// build starts (R:196, `mktemp` before the build).
  ///
  /// A file counts as made by the build only if it was written after this
  /// time. The time comes from a file the implementation writes right now, so
  /// it is in the same clock as the modification times of the artifacts, not
  /// the engine's clock, and a skew between the two cannot matter.
  Future<DateTime> markBuildStart();

  /// The file at [path], or `null` if there is none.
  Future<BuildFile?> stat(String path);

  /// Every file called exactly [name] anywhere below [directory]; empty if
  /// the directory does not exist.
  Future<List<BuildFile>> find(String directory, {required String name});

  /// The files directly in [directory] whose name ends with [extension]
  /// (`.ipa`); empty if the directory does not exist.
  Future<List<BuildFile>> list(String directory, {required String extension});

  /// Deletes the files directly in [directory] whose name ends with
  /// [extension]. Does nothing if the directory does not exist.
  Future<void> deleteAll(String directory, {required String extension});

  /// The bytes of the file at [path].
  Stream<List<int>> open(String path);
}

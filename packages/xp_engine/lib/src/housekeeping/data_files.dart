/// A worktree under the data directory. Its name is the id of the job it was
/// made for.
class WorktreeDirectory {
  /// Creates the description.
  const new({
    required this.key,
    required this.name,
    required this.path,
    required this.bytes,
  });

  /// The key of the mirror it belongs to (`GitMirror.key`).
  final String key;

  /// The folder name: the job's id.
  final String name;

  /// The absolute path.
  final String path;

  /// The size of the folder in bytes.
  final int bytes;
}

/// A mirror under the data directory.
class MirrorDirectory {
  /// Creates the description.
  const new({required this.key, required this.path, required this.bytes});

  /// Its key (`GitMirror.key`): the source key of the project it mirrors.
  final String key;

  /// The absolute path.
  final String path;

  /// The size of the folder in bytes.
  final int bytes;
}

/// A Flutter SDK in XPath's cache (D-20).
class FlutterDirectory {
  /// Creates the description.
  const new({required this.version, required this.path, required this.bytes});

  /// The exact version, such as `3.47.6`: the folder name.
  final String version;

  /// The absolute path.
  final String path;

  /// The size of the folder in bytes.
  final int bytes;
}

/// The folders of the data directory that housekeeping measures and removes:
/// job logs, worktrees, mirrors and the Flutter cache.
///
/// `xp_adapters` has the implementation for the real data directory. The
/// artifact files go through the `ArtifactStore`.
abstract interface class DataFiles {
  /// The size in bytes of the log folder of every job that has one, by job id.
  Future<Map<String, int>> logSizes();

  /// Deletes the logs of the job [jobId]. Does nothing if there are none.
  Future<void> deleteLogs(String jobId);

  /// Every worktree.
  Future<List<WorktreeDirectory>> worktrees();

  /// Forgets and deletes [worktree].
  Future<void> deleteWorktree(WorktreeDirectory worktree);

  /// Every mirror.
  Future<List<MirrorDirectory>> mirrors();

  /// Deletes [mirror] and what is left of the worktrees of its repository.
  Future<void> deleteMirror(MirrorDirectory mirror);

  /// Every Flutter SDK in the cache.
  Future<List<FlutterDirectory>> flutterVersions();

  /// Deletes [sdk].
  Future<void> deleteFlutterVersion(FlutterDirectory sdk);
}

/// [DataFiles] over data the test sets; remembers what was deleted.
class InMemoryDataFiles implements DataFiles {
  /// The log sizes by job id.
  final logs = <String, int>{};

  /// The worktrees.
  final worktreeList = <WorktreeDirectory>[];

  /// The mirrors.
  final mirrorList = <MirrorDirectory>[];

  /// The SDKs.
  final sdks = <FlutterDirectory>[];

  /// What was deleted, as `kind name`, oldest first.
  final deleted = <String>[];

  /// If set, deleting the item with this `kind name` throws.
  String? failOn;

  void _check(String what) {
    if (what == failOn) throw StateError('Cannot delete $what.');
  }

  @override
  Future<Map<String, int>> logSizes() async => Map.of(logs);

  @override
  Future<void> deleteLogs(String jobId) async {
    _check('logs $jobId');
    logs.remove(jobId);
    deleted.add('logs $jobId');
  }

  @override
  Future<List<WorktreeDirectory>> worktrees() async => List.of(worktreeList);

  @override
  Future<void> deleteWorktree(WorktreeDirectory worktree) async {
    _check('worktree ${worktree.name}');
    worktreeList.remove(worktree);
    deleted.add('worktree ${worktree.name}');
  }

  @override
  Future<List<MirrorDirectory>> mirrors() async => List.of(mirrorList);

  @override
  Future<void> deleteMirror(MirrorDirectory mirror) async {
    _check('mirror ${mirror.key}');
    mirrorList.remove(mirror);
    deleted.add('mirror ${mirror.key}');
  }

  @override
  Future<List<FlutterDirectory>> flutterVersions() async => List.of(sdks);

  @override
  Future<void> deleteFlutterVersion(FlutterDirectory sdk) async {
    _check('flutter ${sdk.version}');
    sdks.remove(sdk);
    deleted.add('flutter ${sdk.version}');
  }
}

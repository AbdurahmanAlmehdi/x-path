import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xp_engine/xp_engine.dart';

/// The folders of the data directory that housekeeping measures and removes:
/// `logs/<job id>`, `worktrees/<repository id>/<job id>`,
/// `mirrors/<repository id>.git` and `toolchains/flutter/<version>`.
///
/// A worktree is forgotten by its mirror before its folder goes (the git
/// service's `removeWorktree`), so the mirror does not keep a record of a
/// folder that is gone.
class DirectoryDataFiles implements DataFiles {
  /// Creates the files of [dataDir]; the git service removes worktrees.
  const new({required this.dataDir, required this._git});

  /// The data directory.
  final String dataDir;

  final GitService _git;

  String get _logs => p.join(dataDir, 'logs');
  String get _worktrees => p.join(dataDir, 'worktrees');
  String get _mirrors => p.join(dataDir, 'mirrors');
  String get _flutter => p.join(dataDir, 'toolchains', 'flutter');

  static final _mirrorName = RegExp(r'^(\d+|h[0-9a-f]{16})\.git$');

  @override
  Future<Map<String, int>> logSizes() async => {
    for (final directory in _directories(_logs))
      p.basename(directory.path): await _sizeOf(directory),
  };

  @override
  Future<void> deleteLogs(String jobId) async =>
      _delete(Directory(p.join(_logs, _plain(jobId))));

  @override
  Future<List<WorktreeDirectory>> worktrees() async => [
    for (final repository in _directories(_worktrees))
      if (p.basename(repository.path) case final key
          when GitMirror.keyPattern.hasMatch(key))
        for (final directory in _directories(repository.path))
          WorktreeDirectory(
            key: key,
            name: p.basename(directory.path),
            path: directory.path,
            bytes: await _sizeOf(directory),
          ),
  ];

  @override
  Future<void> deleteWorktree(WorktreeDirectory worktree) async {
    await _git.removeWorktree(
      GitWorktree(
        mirror: _mirrorOf(worktree.key),
        path: worktree.path,
        sha: '',
      ),
    );
    // The folder of a repository with no worktree left is not needed.
    final parent = Directory(p.dirname(worktree.path));
    if (parent.existsSync() && parent.listSync().isEmpty) parent.deleteSync();
  }

  @override
  Future<List<MirrorDirectory>> mirrors() async => [
    for (final directory in _directories(_mirrors))
      if (_mirrorName.firstMatch(p.basename(directory.path)) case final match?)
        MirrorDirectory(
          key: match.group(1)!,
          path: directory.path,
          bytes: await _sizeOf(directory),
        ),
  ];

  @override
  Future<void> deleteMirror(MirrorDirectory mirror) async {
    _delete(Directory(mirror.path));
    _delete(Directory(p.join(_worktrees, mirror.key)));
  }

  @override
  Future<List<FlutterDirectory>> flutterVersions() async => [
    for (final directory in _directories(_flutter))
      // `.install-*` is an installation under way.
      if (!p.basename(directory.path).startsWith('.'))
        FlutterDirectory(
          version: p.basename(directory.path),
          path: directory.path,
          bytes: await _sizeOf(directory),
        ),
  ];

  @override
  Future<void> deleteFlutterVersion(FlutterDirectory sdk) async =>
      _delete(Directory(p.join(_flutter, _plain(sdk.version))));

  GitMirror _mirrorOf(String key) =>
      GitMirror(key: key, path: p.join(_mirrors, '$key.git'));

  /// The folders directly inside [path], by name.
  List<Directory> _directories(String path) {
    final directory = Directory(path);
    if (!directory.existsSync()) return const [];
    return [
      for (final entry in directory.listSync(followLinks: false))
        if (entry is Directory) entry,
    ]..sort((a, b) => a.path.compareTo(b.path));
  }

  /// The size of the files below [directory]. It reads the folder
  /// asynchronously (a Flutter SDK has tens of thousands of files, and the
  /// engine has jobs to serve meanwhile); links are not followed.
  Future<int> _sizeOf(Directory directory) async {
    var total = 0;
    await for (final entry in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entry is File) total += await entry.length();
    }
    return total;
  }

  void _delete(Directory directory) {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  }

  /// [name] if it is one plain path segment, so that an id read from the
  /// database can never reach outside the folder.
  String _plain(String name) {
    if (name.isEmpty ||
        name == '.' ||
        name == '..' ||
        name.contains('/') ||
        name.contains(r'\') ||
        name.contains('\x00')) {
      throw ArgumentError.value(name, 'name', 'is not a plain name');
    }
    return name;
  }
}

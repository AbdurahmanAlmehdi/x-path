import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xp_engine/xp_engine.dart';

/// Secret files in a directory per job: `<root>/<jobId>/<name>`.
///
/// The directory of a job is private to the engine's user (0700) and so is
/// every file (0600), made so before any secret is written to it.
class DirectorySecretFileStore implements SecretFileStore {
  /// Creates a store under [root].
  ///
  /// `runProcess` runs `chmod`; tests replace it.
  const new(this.root, {this._runProcess = Process.run});

  /// The directory that holds one folder per job.
  final String root;

  final Future<ProcessResult> Function(String, List<String>) _runProcess;

  @override
  Future<String> write(String jobId, String name, String contents) async {
    if (name != p.basename(name) || name.isEmpty || name == '..') {
      throw ArgumentError.value(name, 'name', 'Not a plain file name');
    }
    final directory = Directory(p.join(root, jobId));
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
      await _chmod('700', directory.path);
    }
    final file = File(p.join(directory.path, name))..createSync();
    await _chmod('600', file.path);
    await file.writeAsString(contents);
    return file.path;
  }

  @override
  Future<void> deleteAll(String jobId) async {
    final directory = Directory(p.join(root, jobId));
    if (directory.existsSync()) await directory.delete(recursive: true);
  }

  Future<void> _chmod(String mode, String path) async {
    final result = await _runProcess('chmod', [mode, path]);
    if (result.exitCode != 0) {
      throw FileSystemException('chmod $mode failed: ${result.stderr}', path);
    }
  }
}

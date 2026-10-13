import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:xp_engine/xp_engine.dart';

/// Short-lived files for secrets in a directory of the engine's data folder
/// (`<data-dir>/tmp/credentials`).
///
/// The directory is private to the engine's user (0700) and every file is
/// created with mode 0600 before any secret is written to it. Callers delete
/// the file as soon as they are done; the engine also empties the directory
/// when it starts.
class DirectoryTemporaryFileStore implements TemporaryFileStore {
  /// Creates a store under [root].
  ///
  /// [random] is for tests; it must be cryptographically secure otherwise.
  /// `runProcess` runs `chmod`; tests replace it.
  new(this.root, {Random? random, this._runProcess = Process.run})
    : _random = random ?? Random.secure();

  /// The directory that holds the files.
  final String root;

  final Random _random;
  final Future<ProcessResult> Function(String, List<String>) _runProcess;

  @override
  Future<TemporaryFile> create(List<int> bytes) async {
    final directory = Directory(root);
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
      await _chmod('700', directory.path);
    }
    final name = List.generate(
      12,
      (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final file = File(p.join(root, name))..createSync(exclusive: true);
    await _chmod('600', file.path);
    await file.writeAsBytes(bytes);
    return _DirectoryFile(file);
  }

  /// Deletes every file left behind, for the start of the engine.
  Future<void> deleteAll() async {
    final directory = Directory(root);
    if (directory.existsSync()) await directory.delete(recursive: true);
  }

  Future<void> _chmod(String mode, String path) async {
    final result = await _runProcess('chmod', [mode, path]);
    if (result.exitCode != 0) {
      throw FileSystemException('chmod $mode failed: ${result.stderr}', path);
    }
  }
}

class _DirectoryFile implements TemporaryFile {
  const new(this._file);

  final File _file;

  @override
  String get path => _file.path;

  @override
  Future<void> delete() async {
    if (_file.existsSync()) await _file.delete();
  }
}

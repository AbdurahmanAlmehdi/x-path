import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xp_adapters/xp_adapters.dart';

/// The name of the database file in the data directory.
const databaseFileName = 'xpath.db';

/// Opens the engine database in [directory], creating both if needed.
///
/// A new directory is private to the user (0700) and so is a new database
/// file (0600); SQLite gives its `-wal` and `-shm` files the same mode.
/// `runProcess` runs `chmod`; tests replace it. [onNote] hears what a
/// migration does to the data that is there.
Future<SqliteDatabase> openEngineDatabase(
  String directory, {
  Future<ProcessResult> Function(String, List<String>) runProcess = Process.run,
  void Function(String note)? onNote,
}) async {
  Future<void> chmod(String mode, String path) async {
    final result = await runProcess('chmod', [mode, path]);
    if (result.exitCode != 0) {
      throw FileSystemException('chmod $mode failed: ${result.stderr}', path);
    }
  }

  final dir = Directory(directory);
  if (!dir.existsSync()) {
    await dir.create(recursive: true);
    await chmod('700', dir.path);
  }
  final file = File(p.join(directory, databaseFileName));
  if (!file.existsSync()) {
    file.createSync();
    await chmod('600', file.path);
  }
  return SqliteDatabase.open(file.path, onNote: onNote);
}

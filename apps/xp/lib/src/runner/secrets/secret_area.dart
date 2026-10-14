import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:xp/src/runner/runner_paths.dart';
import 'package:xp_adapters/xp_adapters.dart';

/// Where the secret folders of a runner are.
class SecretLocations {
  /// Creates the locations.
  const new({required this.active, required this.all});

  /// Chooses the places for a runner with the data directory [paths].
  ///
  /// Linux: a tmpfs-backed folder, in `/dev/shm`, else in
  /// `$XDG_RUNTIME_DIR`, so that the secrets never reach the disk. Else (and
  /// on macOS, which has no tmpfs for a user) a 0700 folder in the runner's
  /// data directory. [exists] says whether a directory is there.
  ///
  /// [all] names every place the runner may have used in an earlier run, so
  /// that a start wipes them all, whichever [active] is now.
  factory choose({
    required String operatingSystem,
    required Map<String, String> environment,
    required RunnerPaths paths,
    bool Function(String path)? exists,
  }) {
    final isDirectory = exists ?? (path) => Directory(path).existsSync();
    final name = 'xpath-runner-${_hash(paths.root)}';
    final candidates = [
      if (operatingSystem == 'linux') ...[
        p.join('/dev/shm', name),
        if (environment['XDG_RUNTIME_DIR'] case final runtime?
            when runtime.isNotEmpty)
          p.join(runtime, name),
      ],
    ];
    final fallback = paths.fallbackSecrets;
    final active = candidates.firstWhere(
      (candidate) => isDirectory(p.dirname(candidate)),
      orElse: () => fallback,
    );
    return SecretLocations(active: active, all: [...candidates, fallback]);
  }

  /// Where the secrets of the jobs in flight are.
  final String active;

  /// Every place secrets may have been left in.
  final List<String> all;

  static String _hash(String text) =>
      sha256.convert(utf8.encode(text)).toString().substring(0, 12);
}

/// The folders that hold the secrets of the jobs that run: one folder per job
/// (0700, its files 0600), deleted when the job ends and, whatever a crash
/// left, when the runner starts (D-09).
///
/// What goes in: the secret files a step asks for (`secretFiles`, written by
/// the job runner), and every secret the engine delivered, kept so that a
/// secret is asked for once per lease.
class SecretArea {
  /// Creates the area at [locations].
  ///
  /// `runProcess` runs `chmod`; tests replace it.
  new(
    this.locations, {
    Future<ProcessResult> Function(String, List<String>) runProcess =
        Process.run,
  }) : _runProcess = runProcess,
       files = DirectorySecretFileStore(
         locations.active,
         runProcess: runProcess,
       );

  /// Where the folders are.
  final SecretLocations locations;

  /// The secret files of jobs, for the job runner.
  final DirectorySecretFileStore files;

  final Future<ProcessResult> Function(String, List<String>) _runProcess;

  /// Deletes everything an earlier run left in any of the places, and makes
  /// the active one ready (0700). Returns how many job folders it removed.
  Future<int> wipeAll() async {
    var removed = 0;
    for (final path in locations.all) {
      final directory = Directory(path);
      if (!directory.existsSync()) continue;
      for (final entry in directory.listSync()) {
        entry.deleteSync(recursive: true);
        removed++;
      }
      if (path != locations.active) directory.deleteSync();
    }
    final active = Directory(locations.active);
    await active.create(recursive: true);
    final result = await _runProcess('chmod', ['700', active.path]);
    if (result.exitCode != 0) {
      throw FileSystemException(
        'chmod 700 failed: ${result.stderr}',
        active.path,
      );
    }
    return removed;
  }

  /// Keeps the delivered secret [key] of the job [jobId] in the job's folder.
  Future<void> keep(String jobId, String key, List<int> value) async {
    await files.writeBytes(jobId, _fileName(key), value);
  }

  /// The delivered secret [key] of the job [jobId], if it was kept.
  Future<List<int>?> recall(String jobId, String key) async {
    final file = File(p.join(locations.active, jobId, _fileName(key)));
    return file.existsSync() ? await file.readAsBytes() : null;
  }

  /// Deletes the folder of the job [jobId].
  Future<void> deleteJob(String jobId) => files.deleteAll(jobId);

  static String _fileName(String key) {
    final digest = sha256.convert(utf8.encode(key)).toString();
    return 'delivered-${digest.substring(0, 16)}';
  }
}

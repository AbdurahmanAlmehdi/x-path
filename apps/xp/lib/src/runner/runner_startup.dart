import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xp/src/runner/job/pgid_journal.dart';
import 'package:xp/src/runner/runner_paths.dart';
import 'package:xp/src/runner/secrets/secret_area.dart';
import 'package:xp/src/runner/secrets/temporary_keychain.dart';
import 'package:xp_engine/xp_engine.dart';

/// What a start of the runner found left by a runner that died, and removed.
class StartupReport {
  /// Creates the report.
  const new({
    this.processGroups = 0,
    this.secretFolders = 0,
    this.keychains = 0,
    this.workFolders = 0,
  });

  /// The process groups of steps that were still alive and were stopped.
  final int processGroups;

  /// The folders of secrets that were deleted.
  final int secretFolders;

  /// The temporary keychains that were deleted.
  final int keychains;

  /// The work folders and worktrees of jobs that were deleted.
  final int workFolders;

  /// Whether there was nothing to clean up.
  bool get isClean =>
      processGroups + secretFolders + keychains + workFolders == 0;

  /// A sentence for the owner.
  String describe() => isClean
      ? 'Nothing was left by an earlier run.'
      : 'Cleaned up after an earlier run: stopped $processGroups process '
            'groups, deleted $secretFolders secret folders, $keychains '
            'temporary keychains and $workFolders job folders.';
}

/// Cleans up after a runner that died while it ran jobs (D-09): stops the
/// processes of its steps, wipes the secret folders and temporary keychains
/// of its jobs, and removes their worktrees and work folders. The runner does
/// it first of all when it starts, whatever the reason it stopped; secrets
/// never stay on the machine across runs.
Future<StartupReport> cleanUpAfterCrash({
  required RunnerPaths paths,
  required SecretArea secrets,
  required PgidJournal journal,
  required ProcessGroupKiller killer,
  required ProcessRunner runner,
  required bool isMacOS,
}) async {
  // Processes first: they may hold files of the folders that go.
  final groups = await journal.reap(killer);
  final folders = await secrets.wipeAll();
  final keychains = isMacOS
      ? await TemporaryKeychain.removeLeftovers(
          runner: runner,
          directory: paths.keychains,
        )
      : 0;
  final work = _clear(paths.jobs) + _clear(p.join(paths.source, 'worktrees'));
  // Git still lists the worktrees that were deleted.
  final mirrors = Directory(p.join(paths.source, 'mirrors'));
  if (mirrors.existsSync()) {
    for (final mirror in mirrors.listSync().whereType<Directory>()) {
      await runner.run('git', [
        'worktree',
        'prune',
      ], workingDirectory: mirror.path);
    }
  }
  return StartupReport(
    processGroups: groups,
    secretFolders: folders,
    keychains: keychains,
    workFolders: work,
  );
}

/// Deletes what is in [path] and returns how many entries it removed.
int _clear(String path) {
  final directory = Directory(path);
  if (!directory.existsSync()) return 0;
  var removed = 0;
  for (final entry in directory.listSync()) {
    entry.deleteSync(recursive: true);
    removed++;
  }
  return removed;
}

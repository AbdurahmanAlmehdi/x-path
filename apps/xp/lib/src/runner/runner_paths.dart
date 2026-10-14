import 'package:path/path.dart' as p;

/// Where a runner keeps its files (`--data-dir`).
///
/// ```text
/// runner.json               who the runner is (engine, id, name), no secret
/// secrets.enc, master.key   the credential, on Linux and in file mode
/// source/mirrors/<id>.git   the bare cache of a repository (ADR 0009)
/// source/worktrees/<id>/    the fresh worktree of each job
/// jobs/<job id>/            what a job leaves: its artifacts before upload
/// toolchains/flutter/       the Flutter SDKs the jobs pin
/// secrets/                  secret folders, where no tmpfs is available
/// keychains/                temporary keychains (macOS)
/// state/                    the process groups of running steps
/// versions/<version>/       the installed `xp` bundles (`bin/xp`, `lib/`)
/// current                   a symlink to the version that starts (D-24)
/// updates/                  bundles on their way in, deleted after
/// update.json               the update in progress, and the version to avoid
/// service-logs/             what the LaunchAgent writes (macOS)
/// ```
class RunnerPaths {
  /// The layout under [root].
  const new(this.root);

  /// The data directory: `$XP_RUNNER_DATA_DIR`, else
  /// `$XDG_DATA_HOME/xpath/runner`, else `~/.local/share/xpath/runner`.
  factory fromEnvironment(Map<String, String> environment, String home) {
    final explicit = environment[dataDirVariable];
    if (explicit != null && explicit.isNotEmpty) return RunnerPaths(explicit);
    final xdg = environment['XDG_DATA_HOME'];
    final base = xdg != null && xdg.isNotEmpty
        ? xdg
        : p.join(home, '.local', 'share');
    return RunnerPaths(p.join(base, 'xpath', 'runner'));
  }

  /// The variable that names the data directory.
  static const dataDirVariable = 'XP_RUNNER_DATA_DIR';

  /// The data directory.
  final String root;

  /// Who the runner is.
  String get identityFile => p.join(root, 'runner.json');

  /// The runner's own git data: bare caches and worktrees.
  String get source => p.join(root, 'source');

  /// The work folders of jobs.
  String get jobs => p.join(root, 'jobs');

  /// The work folder of the job [jobId].
  String jobDirectory(String jobId) => p.join(jobs, jobId);

  /// The Flutter SDK cache.
  String get flutterToolchains => p.join(root, 'toolchains', 'flutter');

  /// The secret folders where no tmpfs is available.
  String get fallbackSecrets => p.join(root, 'secrets');

  /// The temporary keychains.
  String get keychains => p.join(root, 'keychains');

  /// The record of running process groups.
  String get state => p.join(root, 'state');

  /// The installed bundles of `xp`, one folder per version.
  String get versions => p.join(root, 'versions');

  /// The folder of the bundle of [version].
  String versionDirectory(String version) => p.join(versions, version);

  /// The symlink to the version of `versions/` that the runner starts as. The
  /// service runs `current/bin/xp`; an update switches the link.
  String get currentLink => p.join(root, 'current');

  /// The `xp` the service runs.
  String get currentExecutable => p.join(currentLink, 'bin', 'xp');

  /// Where a bundle lands before it is unpacked.
  String get updates => p.join(root, 'updates');

  /// The record of an update that has not proven itself yet.
  String get updateState => p.join(root, 'update.json');

  /// Where the LaunchAgent writes the output of the runner.
  String get serviceLogs => p.join(root, 'service-logs');
}

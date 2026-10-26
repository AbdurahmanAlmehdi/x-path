import 'package:xp/src/runner/job/leased_job.dart';
import 'package:xp/src/runner/job/remote_checkout_step.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';

/// The steps a runner can run, made with what a runner has: its own git, its
/// own toolchain cache, local records of what the job builds, and the secrets
/// the engine delivers for the one job.
///
/// A runner runs the steps the engine allows it (`RemoteStepPolicy`): the
/// ones that build, check what was built and make files. It runs none that
/// publish (`upload.*`, `git.push`, `github.*`), approve (`gate`), ask the
/// stores (`guard`) or need the engine's records (`test`): those stay on the
/// engine (D-09, D-13).
class RunnerSteps {
  /// Creates the factory for a machine whose git data is `git`.
  const new({
    required this._runner,
    required this._git,
    required this._clock,
    required this._flutterToolchains,
    required this._isMacOS,
    required this._queues,
    this._iosLinux,
    this._testSourceUrl,
  });

  final ProcessRunner _runner;
  final GitService _git;
  final Clock _clock;
  final String _flutterToolchains;
  final bool _isMacOS;
  final SerialQueues _queues;

  /// The omarchy-apple-dev checkout and the folder of the Flutter installs
  /// Linux iOS builds prepare, on a Linux runner set up for them (ADR 0014).
  final ({String directory, String installs})? _iosLinux;
  final String? _testSourceUrl;

  /// The step kinds of every registry this makes.
  static const kinds = {
    'analyze',
    'build.android',
    'build.ios',
    'build.verifyCompiledConfig',
    'command',
    'git.checkout',
    'ios.stripAndReexport',
    'record.manifest',
    'shorebird.patch',
    'shorebird.release',
    'symbols.archive',
    'version.bump',
  };

  /// The steps for the lease with `services`.
  StepRegistry registry(LeaseServices services) {
    const files = DirectoryBuildFiles();
    const directories = DirectoryBuildDirectories();
    final toolchain = BuildToolchain(
      resolver: FlutterResolver(
        runner: _runner,
        installer: GitFlutterInstaller(
          root: _flutterToolchains,
          runner: _runner,
        ),
      ),
      prober: ToolProber(runner: _runner, isMacOS: _isMacOS),
      jobs: services.jobs,
    );
    final iosLinux = _isMacOS ? null : _iosLinux;
    final linux = iosLinux == null
        ? null
        : IosLinuxBuilds(
            toolchain: BuildToolchain(
              resolver: FlutterResolver(
                runner: _runner,
                installer: GitFlutterInstaller(
                  root: iosLinux.installs,
                  runner: _runner,
                ),
                useFvm: false,
              ),
              prober: ToolProber(runner: _runner, isMacOS: _isMacOS),
              jobs: services.jobs,
            ),
            checkout: DirectoryIosLinuxToolchain(
              directory: iosLinux.directory,
              installs: iosLinux.installs,
              runner: _runner,
              clock: _clock,
            ),
          );
    final recorder = ArtifactRecorder(
      store: services.artifactStore,
      repository: services.artifacts,
      clock: _clock,
    );
    final shorebird = ShorebirdCliReleases(
      runner: _runner,
      secrets: services.secrets,
    );
    final records = InMemoryShorebirdReleaseRepository();
    return StepRegistry([
      const CommandStep(),
      RemoteCheckoutStep(
        source: services.source,
        queues: _queues,
        testUrl: _testSourceUrl,
      ),
      VersionBumpStep(git: _git, workspaces: DirectoryWorkspace.new),
      BuildAndroidStep(
        toolchain: toolchain,
        files: files,
        recorder: recorder,
        repository: services.artifacts,
        store: services.artifactStore,
      ),
      BuildIosStep(
        toolchain: toolchain,
        files: files,
        recorder: recorder,
        repository: services.artifacts,
        store: services.artifactStore,
        isMacOS: _isMacOS,
        linux: linux,
      ),
      ShorebirdReleaseStep(
        toolchain: toolchain,
        files: files,
        recorder: recorder,
        repository: services.artifacts,
        store: services.artifactStore,
        releases: shorebird,
        records: records,
        clock: _clock,
        isMacOS: _isMacOS,
      ),
      ShorebirdPatchStep(
        toolchain: toolchain,
        files: files,
        releases: shorebird,
        records: records,
        isMacOS: _isMacOS,
      ),
      SymbolsArchiveStep(
        directories: directories,
        files: files,
        recorder: recorder,
        repository: services.artifacts,
        store: services.artifactStore,
      ),
      VerifyCompiledConfigStep(
        workspaces: DirectoryWorkspace.new,
        repository: services.artifacts,
        store: services.artifactStore,
        snapshots: const ZipSnapshotReader(),
      ),
      StripAndReexportStep(
        directories: directories,
        files: files,
        recorder: recorder,
        isMacOS: _isMacOS,
      ),
      RecordManifestStep(
        git: _git,
        workspaces: DirectoryWorkspace.new,
        artifacts: services.artifacts,
        recorder: recorder,
        jobs: services.jobs,
        clock: _clock,
      ),
      AnalyzeStep(toolchain: toolchain),
    ]);
  }
}

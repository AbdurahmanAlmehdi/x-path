import 'dart:async';
import 'dart:io' as io;

import 'package:path/path.dart' as p;
import 'package:xp/src/config/client_secret_store.dart';
import 'package:xp/src/config/xp_config.dart';
import 'package:xp/src/context.dart';
import 'package:xp/src/runner/job/leased_job.dart';
import 'package:xp/src/runner/job/pgid_journal.dart';
import 'package:xp/src/runner/job/uploading_artifacts.dart';
import 'package:xp/src/runner/no_secrets.dart';
import 'package:xp/src/runner/runner_agent.dart';
import 'package:xp/src/runner/runner_identity.dart';
import 'package:xp/src/runner/runner_paths.dart';
import 'package:xp/src/runner/runner_socket.dart';
import 'package:xp/src/runner/runner_startup.dart';
import 'package:xp/src/runner/runner_steps.dart';
import 'package:xp/src/runner/secrets/secret_area.dart';
import 'package:xp/src/runner/update/runner_updater.dart';
import 'package:xp/src/version.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xp_secrets/xp_secrets.dart';

/// The variable that replaces the repository URL of every lease, for
/// end-to-end tests only: they point it at a local repository, as there is no
/// GitHub (and no SSH key) to fetch from. A real runner never sets it.
const testSourceUrlVariable = 'XP_RUNNER_TEST_SOURCE_URL';

/// The variable that names the omarchy-apple-dev checkout of a runner that
/// builds iOS apps on Linux. `xp runner start` and `xp runner doctor` read
/// it, and `xp runner install-service` writes it into the service when it is
/// set.
const iosLinuxDirectoryVariable = 'XP_IOS_LINUX_DIR';

/// What `xp runner` needs to know of the machine it runs on. Tests pass their
/// own.
class RunnerHost {
  /// Creates the description of a machine.
  const new({
    required this.operatingSystem,
    required this.cores,
    required this.pid,
    required this.environment,
    required this.runner,
    this.openCredentials,
    this.executable = '',
  });

  /// The real machine.
  factory system(Map<String, String> environment) => RunnerHost(
    operatingSystem: io.Platform.operatingSystem,
    cores: io.Platform.numberOfProcessors,
    pid: io.pid,
    environment: environment,
    runner: const IoProcessRunner(),
    executable: io.Platform.resolvedExecutable,
  );

  /// `macos` or `linux`.
  final String operatingSystem;

  /// The processor cores.
  final int cores;

  /// The id of this process.
  final int pid;

  /// The environment variables.
  final Map<String, String> environment;

  /// Starts programs.
  final ProcessRunner runner;

  /// Opens the store of the credential, instead of the usual one. For tests.
  final SecretStore Function(RunnerPaths paths)? openCredentials;

  /// The path of the running `xp` as the operating system resolves it
  /// (`Platform.resolvedExecutable`), or empty when it is not known.
  final String executable;

  /// The folder of the bundle that runs (`<bundle>/bin/xp` and
  /// `<bundle>/lib`), or `null` when `xp` does not run from a bundle (`dart
  /// run`, a test).
  String? get bundle {
    final bin = p.dirname(executable);
    if (p.basename(executable) != 'xp' || p.basename(bin) != 'bin') {
      return null;
    }
    return p.dirname(bin);
  }

  /// Whether this is a Mac.
  bool get isMacOS => operatingSystem == 'macos';

  /// The home directory.
  String get home => environment['HOME'] ?? '';

  /// The omarchy-apple-dev checkout of a runner configured to build iOS apps
  /// on Linux ([iosLinuxDirectoryVariable]), or `null`.
  String? get iosLinuxDirectory =>
      switch (environment[iosLinuxDirectoryVariable]) {
        final directory? when directory.isNotEmpty => directory,
        _ => null,
      };

  /// Where the credential of a runner with the data directory [paths] is
  /// kept: the Keychain on macOS, an encrypted file in the data directory
  /// otherwise (`XP_TEST_FILE_SECRETS=1` forces the file, for tests).
  SecretStore credentials(RunnerPaths paths) {
    final open = openCredentials;
    if (open != null) return open(paths);
    if (isMacOS && environment[fileSecretsVariable] != '1') {
      return KeychainSecretStore(runner: runner, scope: 'runner');
    }
    return EncryptedFileSecretStore(
      dataDir: paths.root,
      runner: runner,
      credentialsDirectory: environment['CREDENTIALS_DIRECTORY'],
    );
  }
}

/// What the runner needs to start.
class RunnerSetup {
  /// Creates the setup.
  const new({
    required this.paths,
    required this.enrollment,
    required this.host,
    required this.log,
    required this.clientFactory,
    this.slots,
    this.oneShot = false,
    this.version = packageVersion,
  });

  /// The data directory.
  final RunnerPaths paths;

  /// Who the runner is and its credential.
  final RunnerEnrollment enrollment;

  /// The machine.
  final RunnerHost host;

  /// Says something to the owner.
  final void Function(String message) log;

  /// Makes a client of the engine.
  final ClientFactory clientFactory;

  /// The `--slots` the owner gave.
  final int? slots;

  /// Whether the runner exits after one job.
  final bool oneShot;

  /// The version of `xp` this runner reports and compares with the engine's.
  /// Only a test passes another one, to play the new version after an update.
  final String version;
}

/// A runner that is ready to run.
abstract interface class RunnerProcess {
  /// Cleans up after an earlier run, then connects and works until the runner
  /// has to end.
  Future<AgentExit> run();

  /// Finish the jobs, take no more, then end.
  void drain();

  /// Stop now: cancel the jobs, report nothing.
  Future<void> stop();
}

/// Makes the runner for [setup].
typedef RunnerBuilder = Future<RunnerProcess> Function(RunnerSetup setup);

/// Assembles the runner of the real machine: the process supervisor of the
/// engine (each step in its own process group, ADR 0003), the engine's step
/// runner with the steps a runner can run, the runner's own git and toolchain
/// caches, its secret folders and the connection to the engine.
Future<RunnerProcess> buildRunner(RunnerSetup setup) async {
  final host = setup.host;
  final paths = setup.paths;
  final environment = host.environment;
  final masker = SecretMasker();
  const clock = SystemClock();
  final supervisor = IoProcessSupervisor(
    masker: masker,
    clock: clock,
    path: environment['PATH'],
  )..requirePerl();
  final client = setup.clientFactory(
    Connection(
      url: setup.enrollment.identity.engine,
      token: setup.enrollment.credential,
    ),
  );
  final secretArea = SecretArea(
    SecretLocations.choose(
      operatingSystem: host.operatingSystem,
      environment: environment,
      paths: paths,
    ),
  );
  final journal = PgidJournal(paths.state);
  final git = CliGitService(
    runner: host.runner,
    secrets: const NoSecrets(),
    dataDir: paths.source,
  );
  final steps = RunnerSteps(
    runner: host.runner,
    git: git,
    clock: clock,
    flutterToolchains: paths.flutterToolchains,
    isMacOS: host.isMacOS,
    queues: SerialQueues(),
    testSourceUrl: environment[testSourceUrlVariable],
  );
  final jobEnvironment = JobEnvironment(
    paths: paths,
    supervisor: supervisor,
    hostEnvironment: environment,
    secretArea: secretArea,
    journal: journal,
    power: ReferenceCountedPowerAssertion(
      createPowerAssertion(
        runner: host.runner,
        operatingSystem: host.operatingSystem,
        pid: host.pid,
        onWarning: (message) => setup.log('Warning: $message'),
      ),
    ),
    clock: clock,
    upload: retrying(uploadThrough(client)),
    removeWorktree: git.removeWorktree,
  );
  final arch = await _architecture(host.runner);
  // A one-shot runner is made for one job and lives for minutes: it does not
  // update (D-24).
  final updater = setup.oneShot
      ? null
      : RunnerUpdater(
          paths: paths,
          version: setup.version,
          os: host.operatingSystem,
          arch: arch,
          runner: host.runner,
          fetch: client.downloadRunnerBundle,
          log: setup.log,
          bundle: host.bundle,
        );
  RunnerAgent makeAgent() => RunnerAgent(
    connect: () async => ChannelRunnerSocket(await client.connectRunner()),
    start: (offer, outbox, requestSecret) => LeasedJob(
      offer: offer,
      outbox: outbox,
      environment: jobEnvironment,
      requestSecret: requestSecret,
      registry: steps.registry,
    ),
    probe: ProbeExecutor(
      runner: host.runner,
      operatingSystem: host.operatingSystem,
    ),
    iosLinuxDirectory: host.iosLinuxDirectory,
    stepKinds: RunnerSteps.kinds,
    log: setup.log,
    version: setup.version,
    os: host.operatingSystem,
    arch: arch,
    cores: host.cores,
    slots: setup.slots ?? defaultSlots(host.cores),
    requestedSlots: setup.slots,
    oneShot: setup.oneShot,
    wantsUpdateTo: updater?.wantsUpdateTo,
    onWelcomed: updater?.connected,
  );
  return _Runner(
    makeAgent: makeAgent,
    updater: updater,
    cleanUp: () => cleanUpAfterCrash(
      paths: paths,
      secrets: secretArea,
      journal: journal,
      killer: ProcessGroupKiller(control: const IoProcessGroupControl()),
      runner: host.runner,
      isMacOS: host.isMacOS,
    ),
    log: setup.log,
    close: client.close,
  );
}

class _Runner implements RunnerProcess {
  new({
    required this._makeAgent,
    required this._updater,
    required this._cleanUp,
    required this._log,
    required this._close,
  }) {
    _agent = _makeAgent();
  }

  final RunnerAgent Function() _makeAgent;
  final RunnerUpdater? _updater;
  final Future<StartupReport> Function() _cleanUp;
  final void Function(String message) _log;
  final void Function() _close;

  late RunnerAgent _agent;
  var _draining = false;
  var _stopped = false;

  @override
  Future<AgentExit> run() async {
    try {
      // A version that never reached the engine goes back before it does
      // anything else.
      if (_updater?.checkStart() != null) return AgentExit.updated;
      _log((await _cleanUp()).describe());
      while (true) {
        final exit = await _agent.run();
        final target = _agent.updateVersion;
        final updater = _updater;
        if (exit != AgentExit.updateRequired ||
            target == null ||
            updater == null) {
          return exit;
        }
        // The agent ended with no job open and no connection: the moment to
        // update.
        final outcome = await updater.update(target);
        if (_stopped) return AgentExit.stopped;
        if (_draining) return AgentExit.drained;
        if (outcome is Updated) return AgentExit.updated;
        // The update failed: go on with the version that works.
        _agent = _makeAgent();
      }
    } finally {
      _close();
    }
  }

  @override
  void drain() {
    _draining = true;
    _agent.drain();
  }

  @override
  Future<void> stop() {
    _stopped = true;
    return _agent.stop();
  }
}

/// The machine's architecture as `uname -m` says it, `arm64` for Apple
/// silicon and Linux `aarch64` alike.
Future<String> _architecture(ProcessRunner runner) async {
  try {
    final output = await runner.run('uname', [
      '-m',
    ], timeout: const Duration(seconds: 10));
    final machine = output.stdout.trim();
    if (machine == 'aarch64') return 'arm64';
    return machine.isEmpty ? 'unknown' : machine;
  } on Object {
    return 'unknown';
  }
}

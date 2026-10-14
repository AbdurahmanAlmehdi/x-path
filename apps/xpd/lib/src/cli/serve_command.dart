import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xp_secrets/xp_secrets.dart';
import 'package:xpd/src/cli/xpd_command.dart';
import 'package:xpd/src/credentials/credential_checks.dart';
import 'package:xpd/src/server/xpd_server.dart';
import 'package:xpd/src/stores/apple_stores.dart';
import 'package:xpd/src/stores/firebase_stores.dart';
import 'package:xpd/src/stores/play_stores.dart';
import 'package:xpd/src/stores/store_guard_checks.dart';
import 'package:xpd/src/test_endpoints.dart';
import 'package:xpd/src/version.dart';

/// The port `xpd serve` listens on unless told otherwise.
const defaultPort = 7480;

/// `xpd serve`: runs the engine until SIGINT or SIGTERM.
class ServeCommand extends XpdCommand {
  /// Creates the command.
  new(super.context) {
    argParser
      ..addOption(
        'host',
        help:
            'Address to listen on. Anything but a loopback address exposes '
            'the engine to the network, without encryption.',
        defaultsTo: '127.0.0.1',
      )
      ..addOption(
        'port',
        help: 'Port to listen on. 0 picks a free port.',
        defaultsTo: '$defaultPort',
      )
      ..addOption(
        'slots',
        help:
            'How many jobs run at once on this machine. iOS signing jobs run '
            'one at a time whatever this is.\n'
            '(defaults to a quarter of the processor cores, at least 1)',
        valueHelp: 'n',
      );
  }

  @override
  String get name => 'serve';

  @override
  String get description => 'Run the engine.';

  @override
  Future<int> run() async {
    final host = argResults!['host'] as String;
    final port = int.tryParse(argResults!['port'] as String);
    if (port == null || port < 0 || port > 65535) {
      usageException('--port must be a number from 0 to 65535.');
    }
    final isLoopback =
        host == 'localhost' ||
        (InternetAddress.tryParse(host)?.isLoopback ?? false);
    if (!isLoopback) {
      context.err.writeln(
        'warning: $host is not a loopback address; anyone who can reach it '
        'can try device tokens, and traffic is not encrypted.',
      );
    }

    final slots = argResults!.option('slots') == null
        ? defaultSlots(Platform.numberOfProcessors)
        : int.tryParse(argResults!.option('slots')!);
    if (slots == null || slots < 1) {
      usageException('--slots must be a whole number of at least 1.');
    }

    final testing = TestEndpoints.fromEnvironment(context.environment);
    if (testing.isActive) {
      context.err.writeln(
        'warning: XPD_TEST_* is set, so this engine talks to test servers '
        'or keeps secrets in a file. Use it for end-to-end tests only.',
      );
    }

    final int targetSdk;
    try {
      targetSdk = PlayStores.targetSdkFrom(
        context.environment[playTargetSdkVariable],
      );
    } on FormatException catch (error) {
      context.err.writeln('xpd: ${error.message}');
      return 1;
    }

    final directory = dataDirectory;
    final masker = SecretMasker();
    final supervisor = IoProcessSupervisor(
      masker: masker,
      clock: const SystemClock(),
      path: context.environment['PATH'],
    );
    try {
      supervisor.requirePerl();
    } on ToolchainException catch (error) {
      context.err.writeln('xpd: ${error.message}');
      return 1;
    }
    return await withDatabase((database) async {
      const runner = IoProcessRunner();
      final secrets = createSecretStore(
        runner: runner,
        dataDir: directory,
        operatingSystem: testing.secretStoreSystem(context.operatingSystem),
        environment: context.environment,
      );
      final github = HttpGitHubClient(
        secrets: secrets,
        baseUrl: testing.githubApiUrl,
      );
      final events = SqliteEventLog(
        database: database,
        clock: const SystemClock(),
      );
      final git = CliGitService(
        runner: runner,
        secrets: secrets,
        dataDir: directory,
      );
      final jobRepository = SqliteJobRepository(database);
      final artifactRepository = SqliteArtifactRepository(database);
      final artifactStore = DirectoryArtifactStore(
        p.join(directory, 'artifacts'),
      );
      final artifactRecorder = ArtifactRecorder(
        store: artifactStore,
        repository: artifactRepository,
        clock: const SystemClock(),
      );
      final testRuns = SqliteTestRunRepository(database);
      final projectRepository = SqliteProjectRepository(database);
      final apple = AppleStores(
        database: database,
        secrets: secrets,
        clock: const SystemClock(),
      );
      final play = PlayStores(
        database: database,
        secrets: secrets,
        clock: const SystemClock(),
        requiredTargetSdk: targetSdk,
      );
      final firebase = FirebaseStores(
        clock: const SystemClock(),
        baseUrl: testing.firebaseUrl,
      );
      final credentialChecks = CredentialChecks(
        database: database,
        secrets: secrets,
        projects: projectRepository,
        runner: runner,
        masker: masker,
        events: events,
        clock: const SystemClock(),
        apple: apple,
        play: play,
        firebase: firebase,
        dataDir: directory,
        isMacOS: context.operatingSystem == 'macos',
        githubBaseUrl: testing.githubApiUrl,
        onError: (error, stackTrace) =>
            context.err.writeln('warning: credential check failed: $error'),
      );
      await credentialChecks.temporaryFiles.deleteAll();
      final shorebirdReleases = ShorebirdCliReleases(
        runner: runner,
        secrets: secrets,
      );
      final shorebirdRecords = SqliteShorebirdReleaseRepository(database);
      const buildFiles = DirectoryBuildFiles();
      const buildDirectories = DirectoryBuildDirectories();
      final isMacOS = context.operatingSystem == 'macos';
      final buildToolchain = BuildToolchain(
        resolver: FlutterResolver(
          runner: runner,
          installer: GitFlutterInstaller(
            root: p.join(directory, 'toolchains', 'flutter'),
            runner: runner,
          ),
        ),
        prober: ToolProber(runner: runner, isMacOS: isMacOS),
        jobs: jobRepository,
      );
      final secretFiles = DirectorySecretFileStore(p.join(directory, 'tmp'));
      final logs = JobLogs(store: FileJobLogStore(p.join(directory, 'logs')));
      // Nothing approves a gate yet (Phase 12a), so a job that reaches one
      // waits.
      const approvalGate = PendingApprovalGate();
      final registry = StepRegistry([
        const GateStep(approvalGate),
        GitCheckoutStep(git: git, jobs: jobRepository),
        GitReleaseBranchStep(git),
        GitTagStep(git),
        GitPushStep(git),
        const CommandStep(),
        VersionBumpStep(git: git, workspaces: DirectoryWorkspace.new),
        BuildAndroidStep(
          toolchain: buildToolchain,
          files: buildFiles,
          recorder: artifactRecorder,
          repository: artifactRepository,
          store: artifactStore,
        ),
        BuildIosStep(
          toolchain: buildToolchain,
          files: buildFiles,
          recorder: artifactRecorder,
          repository: artifactRepository,
          store: artifactStore,
          isMacOS: isMacOS,
        ),
        ShorebirdReleaseStep(
          toolchain: buildToolchain,
          files: buildFiles,
          recorder: artifactRecorder,
          repository: artifactRepository,
          store: artifactStore,
          releases: shorebirdReleases,
          records: shorebirdRecords,
          clock: const SystemClock(),
          isMacOS: isMacOS,
        ),
        ShorebirdPatchStep(
          toolchain: buildToolchain,
          files: buildFiles,
          releases: shorebirdReleases,
          records: shorebirdRecords,
          isMacOS: isMacOS,
        ),
        SymbolsArchiveStep(
          directories: buildDirectories,
          files: buildFiles,
          recorder: artifactRecorder,
          repository: artifactRepository,
          store: artifactStore,
        ),
        VerifyCompiledConfigStep(
          workspaces: DirectoryWorkspace.new,
          repository: artifactRepository,
          store: artifactStore,
          snapshots: const ZipSnapshotReader(),
        ),
        StripAndReexportStep(
          directories: buildDirectories,
          files: buildFiles,
          recorder: artifactRecorder,
          isMacOS: isMacOS,
        ),
        RecordManifestStep(
          git: git,
          workspaces: DirectoryWorkspace.new,
          artifacts: artifactRepository,
          recorder: artifactRecorder,
          jobs: jobRepository,
          clock: const SystemClock(),
        ),
        TestStep(
          toolchain: buildToolchain,
          jobs: jobRepository,
          runs: testRuns,
          events: events,
          clock: const SystemClock(),
        ),
        AnalyzeStep(toolchain: buildToolchain),
        apple.uploadStep(
          repository: artifactRepository,
          store: artifactStore,
          secrets: secrets,
          secretFiles: secretFiles,
          isMacOS: isMacOS,
        ),
        play.uploadStep(
          repository: artifactRepository,
          store: artifactStore,
          secrets: secrets,
        ),
        firebase.uploadStep(
          repository: artifactRepository,
          store: artifactStore,
          secrets: secrets,
        ),
        GuardStep(
          checks: [
            const SourceCheck(),
            const VersionSyncCheck(),
            const PatchTargetCheck(),
            const NewReleaseNumberCheck(),
            const PatchNativeDiffCheck(),
            ...storeGuardChecks(apple: apple, play: play),
            credentialChecks.guardCheck,
          ],
          git: git,
          workspaces: DirectoryWorkspace.new,
        ),
      ]);
      final jobs = JobRunner(
        jobs: jobRepository,
        steps: registry,
        supervisor: supervisor,
        logs: logs,
        secrets: secrets,
        secretFiles: secretFiles,
        power: ReferenceCountedPowerAssertion(
          createPowerAssertion(
            runner: runner,
            operatingSystem: context.operatingSystem,
            pid: pid,
            onWarning: (message) => context.err.writeln('warning: $message'),
          ),
        ),
        events: events,
        clock: const SystemClock(),
        hostEnvironment: context.environment,
        onError: (error, stackTrace) =>
            context.err.writeln('error: $error\n$stackTrace'),
      );
      final projects = ProjectService(
        repository: projectRepository,
        github: github,
        git: git,
        scanner: const ProjectScanner(),
        sources: DirectoryScanSource.new,
        runner: runner,
        events: events,
        clock: const SystemClock(),
      );
      final capabilities = await LocalCapabilities(
        runner: runner,
        prober: ToolProber(runner: runner, isMacOS: isMacOS),
        android: DirectoryAndroidSdk(
          environment: context.environment,
          home: context.environment['HOME'],
        ),
        isMacOS: isMacOS,
      ).probe();
      final can = capabilities.isEmpty
          ? 'no capability'
          : capabilities.map((capability) => capability.wire).join(', ');
      context.out.writeln(
        'xpd runs jobs here with $slots slot${slots == 1 ? '' : 's'} and $can',
      );
      final runRepository = SqliteRunRepository(database);
      final scheduler = Scheduler(
        runner: jobs,
        records: jobRepository,
        runs: runRepository,
        events: events,
        runners: [
          LocalRunner(jobs: jobs, capabilities: capabilities, slots: slots),
        ],
        onError: (error, stackTrace) =>
            context.err.writeln('error: scheduler: $error\n$stackTrace'),
      );
      final planners = StepPlanners(registry);
      final workflows = WorkflowService(
        repository: SqliteWorkflowRepository(database),
        projects: projectRepository,
        catalog: planners,
        events: events,
        clock: const SystemClock(),
      );
      final dispatcher = WorkflowDispatcher(
        workflows: workflows,
        planners: planners,
        projects: projectRepository,
        credentials: credentialChecks.repository,
        models: SqliteReleaseModelRepository(database),
        git: git,
        allocator: BuildNumberAllocator(
          counters: SqliteBuildCounterRepository(database),
          stores: CombinedStoreBuildNumbers(
            apple: apple.buildNumbers,
            play: play.buildNumbers,
          ),
          git: git,
        ),
        jobs: jobs,
        records: jobRepository,
        runs: runRepository,
        scheduler: scheduler,
        events: events,
        clock: const SystemClock(),
        workspaces: DirectoryWorkspace.new,
        worktreeAt: (mirror, name) =>
            CliGitService.worktreePath(directory, mirror, name),
      );
      await _recoverJobs(
        JobRecovery(
          jobs: jobRepository,
          killer: ProcessGroupKiller(control: const IoProcessGroupControl()),
          secretFiles: secretFiles,
          events: events,
          clock: const SystemClock(),
        ),
        scheduler,
      );
      // Jobs that were queued when the engine stopped take their turn.
      await scheduler.pump();
      final server = await XpdServer.start(
        tokens: TokenService(
          tokens: SqliteDeviceTokenRepository(database),
          clock: const SystemClock(),
        ),
        events: events,
        projects: projects,
        jobs: scheduler,
        logs: logs,
        artifacts: ArtifactService(
          repository: artifactRepository,
          store: artifactStore,
          jobs: jobRepository,
        ),
        tests: TestRunService(
          runs: testRuns,
          jobs: jobRepository,
          projects: projectRepository,
        ),
        credentials: credentialChecks.service,
        workflows: workflows,
        dispatcher: dispatcher,
        runs: RunService(
          runs: runRepository,
          jobs: jobRepository,
          control: scheduler,
        ),
        clock: const SystemClock(),
        engineVersion: packageVersion,
        host: host,
        port: port,
        onError: (error, stackTrace) =>
            context.err.writeln('error: $error\n$stackTrace'),
      );
      context.out.writeln('xpd listening on ${server.uri}');
      // The first check of credentials that are due must not hold up the
      // engine: each takes a call to a store.
      unawaited(credentialChecks.health.start());

      await context.shutdown.first;
      context.out.writeln('xpd shutting down');
      // Stop the jobs the way a crash would, but cleanly: their processes end
      // and the next start resumes them.
      scheduler.stop();
      await jobs.interruptAll();
      await server.close();
      credentialChecks.close();
      github.close();
      apple.close();
      play.close();
      firebase.close();
      return 0;
    });
  }

  /// Cleans up after an engine that stopped while jobs ran (ADR 0003, D-18):
  /// stops what they left running, and runs the jobs that can simply go on.
  /// Jobs with an interrupted side-effect step wait for an explicit resume.
  Future<void> _recoverJobs(JobRecovery recovery, JobControl jobs) async {
    final report = await recovery.recover();
    for (final id in report.waiting) {
      context.err.writeln(
        'warning: job $id was interrupted in a step with side effects; it '
        'waits for an explicit resume.',
      );
    }
    for (final id in report.resumable) {
      context.out.writeln('resuming interrupted job $id');
      await jobs.resume(id);
    }
  }
}

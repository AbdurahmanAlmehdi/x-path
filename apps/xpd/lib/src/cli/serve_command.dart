import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xp_secrets/xp_secrets.dart';
import 'package:xpd/src/cli/gh_executable.dart';
import 'package:xpd/src/cli/runner_log.dart';
import 'package:xpd/src/cli/xpd_command.dart';
import 'package:xpd/src/cli/xpd_context.dart';
import 'package:xpd/src/credentials/credential_checks.dart';
import 'package:xpd/src/server/xpd_server.dart';
import 'package:xpd/src/service/serve_environment.dart';
import 'package:xpd/src/stores/apple_stores.dart';
import 'package:xpd/src/stores/firebase_stores.dart';
import 'package:xpd/src/stores/play_stores.dart';
import 'package:xpd/src/stores/store_guard_checks.dart';
import 'package:xpd/src/test_endpoints.dart';
import 'package:xpd/src/version.dart';

/// The port `xpd serve` listens on unless told otherwise.
const defaultPort = 7480;

/// The folders `xpd serve` looks in for the runner bundles it hands to
/// runners that have to update (D-24), in order:
///
/// 1. `<data-dir>/bundles/<version>`, where the packaging puts the bundles of
///    this version, and
/// 2. `runners` next to the `bin` and `lib` of the engine's own bundle, when
///    [executable] is `<bundle>/bin/xpd`, and
/// 3. `Contents/Resources/runners` of `XPath.app`, when the engine is the one
///    the app carries (`Contents/Helpers/xpd/bin/xpd`): `Contents/Helpers`
///    may hold only signed code, so `tool/release/build_mac.sh` puts the
///    archives there.
///
/// Each holds `<os>-<arch>/xp.tar.gz`.
List<String> runnerBundleRoots({
  required String dataDirectory,
  required String version,
  required String executable,
}) {
  final binDirectory = p.dirname(executable);
  final bundle = p.dirname(binDirectory);
  final contents = p.dirname(p.dirname(bundle));
  return [
    p.join(dataDirectory, 'bundles', version),
    if (executable.isNotEmpty && p.basename(binDirectory) == 'bin') ...[
      p.join(bundle, 'runners'),
      if (p.basename(p.dirname(bundle)) == 'Helpers' &&
          p.basename(contents) == 'Contents')
        p.join(contents, 'Resources', 'runners'),
    ],
  ];
}

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

  XpdContext? _serving;

  /// While the engine runs: the context with the tool folders on `PATH`
  /// ([withToolDirectories]) and, when launchd started the engine for the
  /// app ([isLaunchedByLaunchd]), the output going to [serveLogPath].
  @override
  XpdContext get context => _serving ?? super.context;

  @override
  Future<int> run() async {
    final base = super.context;
    final environment = withToolDirectories(base.environment);
    final log = isLaunchedByLaunchd(base.environment)
        ? LogFileSink.open(serveLogPath(dataDirectory))
        : null;
    _serving = base.copyWith(out: log, err: log, environment: environment);
    try {
      if (environment['PATH'] != base.environment['PATH']) {
        context.out.writeln('xpd runs tools with PATH=${environment['PATH']}');
      }
      return await _serve();
    } finally {
      _serving = null;
      await log?.close();
    }
  }

  Future<int> _serve() async {
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
      final runner = IoProcessRunner(
        environment: {'PATH': ?context.environment['PATH']},
      );
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
      final releaseRepository = SqliteReleaseRepository(database);
      final releaseModels = SqliteReleaseModelRepository(database);
      final apple = AppleStores(
        database: database,
        secrets: secrets,
        clock: const SystemClock(),
        ascBaseUrl: testing.ascUrl,
        itunesBaseUrl: testing.ascUrl,
      );
      final play = PlayStores(
        database: database,
        secrets: secrets,
        clock: const SystemClock(),
        requiredTargetSdk: targetSdk,
        apiBaseUrl: testing.playUrl,
        uploadBaseUrl: testing.playUrl,
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
      final files = DirectoryDataFiles(dataDir: directory, git: git);
      final logs = JobLogs(store: FileJobLogStore(p.join(directory, 'logs')));
      // A job that reaches a gate waits for the owner (D-13). The service
      // resumes the jobs that wait through the scheduler, which needs the job
      // runner, which needs the steps, which need the service.
      late final Scheduler scheduler;
      final approvals = ApprovalService(
        approvals: SqliteApprovalRepository(database),
        gates: SqliteGateConfigRepository(database),
        projects: projectRepository,
        jobs: jobRepository,
        events: events,
        clock: const SystemClock(),
        resume: (projectId) => scheduler.resumeWaiting(projectId: projectId),
      );
      final registry = StepRegistry([
        GateStep(approvals),
        GitCheckoutStep(git: git, jobs: jobRepository),
        GitReleaseBranchStep(git),
        GitTagStep(git),
        GitPushStep(git),
        GitHubCreatePrStep(github),
        GitHubMergePrStep(github: github, releases: releaseRepository),
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
      final findings = await LocalCapabilities(
        runner: runner,
        operatingSystem: isMacOS ? 'macos' : 'linux',
      ).probe();
      final capabilities = findings.capabilities;
      final can = capabilities.isEmpty
          ? 'no capability'
          : capabilities.map((capability) => capability.wire).join(', ');
      context.out.writeln(
        'xpd runs jobs here with $slots slot${slots == 1 ? '' : 's'} and $can',
      );
      for (final missing in findings.missing) {
        context.out.writeln('no ${missing.capability}: ${missing.explanation}');
      }
      final runRepository = SqliteRunRepository(database);
      final runnerRepository = SqliteRunnerRepository(database);
      scheduler = Scheduler(
        runner: jobs,
        records: jobRepository,
        runs: runRepository,
        events: events,
        runners: [
          LocalRunner(jobs: jobs, capabilities: capabilities, slots: slots),
        ],
        paired: runnerRepository,
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
      final runService = RunService(
        runs: runRepository,
        jobs: jobRepository,
        control: scheduler,
      );
      // The releases dispatch the workflows of new builds and merges, and the
      // dispatcher tells them about the releases it makes.
      late final WorkflowDispatcher dispatcher;
      final releases = ReleaseService(
        releases: releaseRepository,
        jobs: jobRepository,
        runRecords: runRepository,
        runs: runService,
        workflows: workflows,
        poller: ReleaseStatusPoller(
          sources: [
            AppleStatusSource(
              credentials: apple.credentials,
              connect: apple.connect,
              itunes: apple.itunes,
            ),
            PlayStatusSource(
              credentials: play.credentials,
              connect: play.connect,
            ),
          ],
          clock: const SystemClock(),
        ),
        events: events,
        clock: const SystemClock(),
        dispatch: (projectId, workflowId, request) =>
            dispatcher.dispatch(projectId, workflowId, request),
      );
      dispatcher = WorkflowDispatcher(
        workflows: workflows,
        planners: planners,
        projects: projectRepository,
        credentials: credentialChecks.repository,
        models: releaseModels,
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
        releases: releases,
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
      final housekeeping = HousekeepingService(
        planner: HousekeepingPlanner(
          artifacts: artifactRepository,
          jobs: jobRepository,
          releases: releaseRepository,
          projects: projectRepository,
          testRuns: testRuns,
          shorebird: shorebirdRecords,
          files: files,
          clock: const SystemClock(),
        ),
        settings: SqliteHousekeepingRepository(database),
        artifacts: artifactRepository,
        store: artifactStore,
        jobs: jobRepository,
        files: files,
        clock: const SystemClock(),
      );
      // Runners dial out (D-08): the hub holds their connections and leases,
      // places jobs on them through the scheduler, and cancels theirs.
      final tokenService = TokenService(
        tokens: SqliteDeviceTokenRepository(database),
        clock: const SystemClock(),
      );
      // The runners' comings and goings go to the engine log.
      late final RunnerLog runnerLog;
      final runnerHub = RunnerHub(
        runners: runnerRepository,
        projects: projectRepository,
        jobs: jobRepository,
        runner: jobs,
        scheduler: scheduler,
        logs: logs,
        events: events,
        clock: const SystemClock(),
        secrets: secrets,
        masker: masker,
        grants: RunnerSecretGrants(credentialChecks.repository),
        engineVersion: packageVersion,
        onError: (error, stackTrace) =>
            context.err.writeln('error: runner hub: $error\n$stackTrace'),
        onRefused: (name, why) => runnerLog.refused('"$name"', why),
      );
      scheduler.remoteJobs = runnerHub;
      final runnerService = RunnerService(
        runners: runnerRepository,
        pairing: SqlitePairingTokenRepository(database),
        tokens: tokenService,
        presence: runnerHub,
        events: events,
        clock: const SystemClock(),
      );
      runnerLog = RunnerLog(context.out, runnerService);
      final runnerEvents = runnerLog.follow(events);
      final server = await XpdServer.start(
        tokens: tokenService,
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
        githubToken: GitHubTokenService(
          secrets: secrets,
          verifier: credentialChecks.githubVerifier,
          cli: LocatingGitHubCliToken(
            runner: runner,
            secrets: secrets,
            path: context.environment['PATH'],
            fallbacks: context.ghFallbackPaths,
          ),
          masker: masker,
        ),
        workflows: workflows,
        dispatcher: dispatcher,
        runs: runService,
        approvals: approvals,
        releases: releases,
        releaseNotes: ReleaseNotesService(
          releases: releaseRepository,
          projects: projectRepository,
          models: releaseModels,
          git: git,
        ),
        housekeeping: housekeeping,
        runners: runnerService,
        runnerHub: runnerHub,
        runnerArtifacts: RunnerArtifacts(
          recorder: artifactRecorder,
          holdsLease: runnerHub.holdsLease,
        ),
        runnerBundles: DirectoryRunnerBundles(
          runnerBundleRoots(
            dataDirectory: directory,
            version: packageVersion,
            executable: context.executable,
          ),
        ),
        clock: const SystemClock(),
        engineVersion: packageVersion,
        host: host,
        port: port,
        onError: (error, stackTrace) =>
            context.err.writeln('error: $error\n$stackTrace'),
        onRunnerRefused: runnerLog.refused,
      );
      context.out.writeln('xpd listening on ${server.uri}');
      // The owner hears about what matters, in the app and in Slack (D-22).
      final slackWebhook = HttpSlackWebhook();
      final notifier = Notifier(
        events: events,
        factory: NoticeFactory(
          projects: projectRepository,
          releases: releaseRepository,
          jobs: jobRepository,
          runs: runRepository,
          masker: masker,
        ),
        credentials: credentialChecks.repository,
        secrets: secrets,
        slack: SlackSender(webhook: slackWebhook),
        clock: const SystemClock(),
        onError: (error, stackTrace) =>
            context.err.writeln('warning: notification failed: $error'),
      )..start();
      // The first check of credentials that are due must not hold up the
      // engine: each takes a call to a store.
      unawaited(credentialChecks.health.start());
      // Approvals that ran out while the engine was off expire now, and then
      // every minute, so that the jobs that wait for them fail.
      final approvalSweeper = ApprovalSweeper(
        service: approvals,
        onError: (error, stackTrace) =>
            context.err.writeln('warning: approval sweep failed: $error'),
      );
      unawaited(approvalSweeper.start());
      // Releases follow their jobs, and the stores are asked about the ones
      // that wait for them (at most every ten minutes each).
      final releaseWatcher = ReleaseWatcher(
        events: events,
        service: releases,
        onError: (error, stackTrace) =>
            context.err.writeln('warning: release update failed: $error'),
      );
      unawaited(releaseWatcher.start());
      // Logs and job records older than 90 days go once a day (D-24).
      final housekeepingSchedule = HousekeepingSchedule(
        service: housekeeping,
        clock: const SystemClock(),
        onError: (error, stackTrace) =>
            context.err.writeln('warning: housekeeping failed: $error'),
      );
      unawaited(housekeepingSchedule.start());
      // A runner that stops sending heartbeats loses its leases 90 seconds
      // later, and the jobs it held are queued again or wait for a resume
      // (D-08).
      final leaseSweeper = LeaseSweeper(
        hub: runnerHub,
        onError: (error, stackTrace) =>
            context.err.writeln('warning: lease sweep failed: $error'),
      );
      unawaited(leaseSweeper.start());

      await context.shutdown.first;
      context.out.writeln('xpd shutting down');
      // Stop the jobs the way a crash would, but cleanly: their processes end
      // and the next start resumes them.
      scheduler.stop();
      await jobs.interruptAll();
      await server.close();
      approvalSweeper.stop();
      leaseSweeper.stop();
      await releaseWatcher.stop();
      housekeepingSchedule.stop();
      await notifier.stop();
      await runnerEvents.cancel();
      slackWebhook.close();
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

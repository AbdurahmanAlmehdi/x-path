import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xp_secrets/xp_secrets.dart';
import 'package:xpd/src/cli/xpd_command.dart';
import 'package:xpd/src/server/xpd_server.dart';
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
        operatingSystem: context.operatingSystem,
        environment: context.environment,
      );
      final github = HttpGitHubClient(secrets: secrets);
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
      final jobs = JobRunner(
        jobs: jobRepository,
        steps: StepRegistry([
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
          // The checks that need a store (appStoreTrain, playTargetSdk,
          // buildNumberReuse) register with the store adapters (Phase 10).
          GuardStep(
            checks: const [
              SourceCheck(),
              VersionSyncCheck(),
              PatchTargetCheck(),
              NewReleaseNumberCheck(),
              PatchNativeDiffCheck(),
            ],
            git: git,
            workspaces: DirectoryWorkspace.new,
          ),
        ]),
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
      await _recoverJobs(
        JobRecovery(
          jobs: jobRepository,
          killer: ProcessGroupKiller(control: const IoProcessGroupControl()),
          secretFiles: secretFiles,
          events: events,
          clock: const SystemClock(),
        ),
        jobs,
      );
      final server = await XpdServer.start(
        tokens: TokenService(
          tokens: SqliteDeviceTokenRepository(database),
          clock: const SystemClock(),
        ),
        events: events,
        projects: ProjectService(
          repository: SqliteProjectRepository(database),
          github: github,
          git: git,
          scanner: const ProjectScanner(),
          sources: DirectoryScanSource.new,
          runner: runner,
          events: events,
          clock: const SystemClock(),
        ),
        jobs: jobs,
        logs: logs,
        artifacts: ArtifactService(
          repository: artifactRepository,
          store: artifactStore,
          jobs: jobRepository,
        ),
        clock: const SystemClock(),
        engineVersion: packageVersion,
        host: host,
        port: port,
        onError: (error, stackTrace) =>
            context.err.writeln('error: $error\n$stackTrace'),
      );
      context.out.writeln('xpd listening on ${server.uri}');

      await context.shutdown.first;
      context.out.writeln('xpd shutting down');
      // Stop the jobs the way a crash would, but cleanly: their processes end
      // and the next start resumes them.
      await jobs.interruptAll();
      await server.close();
      github.close();
      return 0;
    });
  }

  /// Cleans up after an engine that stopped while jobs ran (ADR 0003, D-18):
  /// stops what they left running, and runs the jobs that can simply go on.
  /// Jobs with an interrupted side-effect step wait for an explicit resume.
  Future<void> _recoverJobs(JobRecovery recovery, JobRunner jobs) async {
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

// Builds the dev APK of the fixture app through the engine's own code path:
// the real job runner, process supervisor, SQLite repositories, git service,
// Flutter resolver and artifact store, against a throwaway data directory and
// a throwaway repository made from the fixture. Run by
// tool/e2e/build_fixture_apk.sh, which checks the result.
//
// There is no workflow engine yet (Phase 11) and no way to start a job over
// HTTP, so this wires the same pieces `xpd serve` wires, creates a job of
// three steps (version.bump, build.android, record.manifest) and runs it.
//
// Usage: dart run tool/build_fixture_apk.dart --fixture <dir> --work <dir>
//          [--flutter-sdk <dir>]
//
// It prints one `artifact <kind> <sha256> <size> <path>` line for each stored
// artifact on standard output; any other output goes to standard error.
// Exits 0 only if the job succeeded.
//
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xp_secrets/xp_secrets.dart';

const _version = '1.0.0+7';
const _flavor = 'dev';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('fixture', mandatory: true, help: 'The fixture app directory.')
    ..addOption('work', mandatory: true, help: 'An empty scratch directory.')
    ..addOption(
      'flutter-sdk',
      help:
          'A Flutter SDK that already is the pinned version. Without it the '
          'resolver finds the pin through fvm, then the cache of XPath, '
          'downloading it if need be.',
    );
  final options = parser.parse(arguments);
  exitCode = await _run(
    fixture: options['fixture'] as String,
    work: options['work'] as String,
    flutterSdk: options['flutter-sdk'] as String?,
  );
}

Future<int> _run({
  required String fixture,
  required String work,
  required String? flutterSdk,
}) async {
  final origin = p.join(work, 'origin');
  final data = p.join(work, 'data');
  Directory(data).createSync(recursive: true);
  _makeRepository(fixture, origin);
  final pin = _flutterPin(fixture);
  _log('Flutter pin: $pin');

  const runner = IoProcessRunner();
  const clock = SystemClock();
  final database = SqliteDatabase.open(p.join(data, 'xpath.db'));
  try {
    final secrets = _NoSecrets();
    final git = CliGitService(runner: runner, secrets: secrets, dataDir: data);
    final mirror = await git.ensureMirror(githubRepoId: 1, remoteUrl: origin);
    await git.fetch(mirror);
    final sha = await git.resolveRef(mirror, 'main');
    final worktree = await git.createWorktree(mirror, name: 'e2e', sha: sha);

    final jobs = SqliteJobRepository(database);
    final artifactRepository = SqliteArtifactRepository(database);
    final artifactStore = DirectoryArtifactStore(p.join(data, 'artifacts'));
    final recorder = ArtifactRecorder(
      store: artifactStore,
      repository: artifactRepository,
      clock: clock,
    );
    final toolchain = BuildToolchain(
      resolver: FlutterResolver(
        runner: runner,
        installer: flutterSdk == null
            ? GitFlutterInstaller(
                root: p.join(data, 'toolchains', 'flutter'),
                runner: runner,
              )
            : _PreinstalledFlutter(flutterSdk),
      ),
      prober: ToolProber(runner: runner, isMacOS: Platform.isMacOS),
      jobs: jobs,
    );
    final supervisor = IoProcessSupervisor(
      masker: SecretMasker(),
      clock: clock,
      path: Platform.environment['PATH'],
    )..requirePerl();
    final versionBump = VersionBumpStep(
      git: git,
      workspaces: DirectoryWorkspace.new,
    );
    final buildAndroid = BuildAndroidStep(
      toolchain: toolchain,
      files: const DirectoryBuildFiles(),
      recorder: recorder,
      repository: artifactRepository,
      store: artifactStore,
    );
    final recordManifest = RecordManifestStep(
      git: git,
      workspaces: DirectoryWorkspace.new,
      artifacts: artifactRepository,
      recorder: recorder,
      jobs: jobs,
      clock: clock,
    );
    final runnerOfJobs = JobRunner(
      jobs: jobs,
      steps: StepRegistry([versionBump, buildAndroid, recordManifest]),
      supervisor: supervisor,
      logs: JobLogs(store: FileJobLogStore(p.join(data, 'logs'))),
      secrets: secrets,
      secretFiles: DirectorySecretFileStore(p.join(data, 'tmp')),
      power: NoPowerAssertion(),
      events: SqliteEventLog(database: database, clock: clock),
      clock: clock,
      hostEnvironment: Platform.environment,
      onError: (error, stackTrace) => _log('engine error: $error\n$stackTrace'),
    );

    _seedProject(database);
    final release = ReleaseWorktree(
      path: worktree.path,
      mirror: mirror,
      sha: sha,
      scope: const TagScope(flavor: _flavor),
    );
    final version = AppVersion.parse(_version);
    final created = await runnerOfJobs.create(
      workflowVersionId: 'wfv_e2e',
      projectId: 'prj_e2e',
      sha: sha,
      steps: [
        StepPlan.of(
          versionBump,
          VersionBumpInput(worktree: release, version: version),
        ),
        StepPlan.of(
          buildAndroid,
          BuildAndroidInput(
            settings: BuildSettings(
              worktree: release,
              version: version,
              flavor: _flavor,
              target: 'lib/main_dev.dart',
              flutterVersion: pin,
            ),
          ),
        ),
        StepPlan.of(
          recordManifest,
          RecordManifestInput(
            worktree: release,
            version: version,
            flavors: const [_flavor],
          ),
        ),
      ],
    );
    _log(
      'Running job ${created.id}: version.bump, build.android, record.manifest',
    );
    await runnerOfJobs.start(created.id);
    final finished = await runnerOfJobs.whenFinished(created.id);

    for (final step in finished.steps) {
      _log(
        'step ${step.ordinal} ${step.kind}: ${step.state.name}'
        '${step.message == null ? '' : ' (${step.message})'}',
      );
    }
    if (finished.state != JobState.succeeded) {
      _log('The job ${finished.state.wire}: ${finished.message}');
      _printLogs(p.join(data, 'logs', created.id));
      return 1;
    }
    _printBuildTail(p.join(data, 'logs', created.id));
    for (final artifact in await artifactRepository.forJob(created.id)) {
      print(
        'artifact ${artifact.kind.wire} ${artifact.sha256} ${artifact.size} '
        '${p.join(data, 'artifacts', artifact.path)}',
      );
    }
    return 0;
  } finally {
    database.close();
  }
}

/// A repository with one commit on `main` that holds the fixture's files.
void _makeRepository(String fixture, String origin) {
  _copy(Directory(fixture), Directory(origin));
  void git(List<String> arguments) {
    final result = Process.runSync('git', [
      '-c',
      'user.name=XPath e2e',
      '-c',
      'user.email=e2e@localhost',
      '-c',
      'commit.gpgsign=false',
      ...arguments,
    ], workingDirectory: origin);
    if (result.exitCode != 0) {
      throw StateError('git ${arguments.join(' ')} failed: ${result.stderr}');
    }
  }

  git(['init', '--quiet', '-b', 'main']);
  git(['add', '--all']);
  git(['commit', '--quiet', '-m', 'fixture']);
}

/// Copies [from] to [to] without build output and tool caches.
void _copy(Directory from, Directory to) {
  const skipped = {'build', '.dart_tool', '.gradle', '.idea'};
  to.createSync(recursive: true);
  for (final entity in from.listSync()) {
    final name = p.basename(entity.path);
    if (skipped.contains(name) || name == 'local.properties') continue;
    final target = p.join(to.path, name);
    if (entity is Directory) {
      _copy(entity, Directory(target));
    } else if (entity is File) {
      entity.copySync(target);
    }
  }
}

String _flutterPin(String fixture) {
  final json = jsonDecode(
    File(p.join(fixture, '.fvmrc')).readAsStringSync(),
  ) as Map<String, dynamic>;
  return json['flutter']! as String;
}

/// A job refers to a project and a workflow version.
void _seedProject(SqliteDatabase database) {
  database.connection
    ..execute(
      'INSERT INTO project (id, host, source_key, github_repo_id, remote, '
      'default_base_branch) '
      "VALUES ('prj_e2e', 'github.com', '1', 1, 'e2e', 'main')",
    )
    ..execute(
      "INSERT INTO workflow (id, project_id, name) VALUES ('wf_e2e', "
      "'prj_e2e', 'build')",
    )
    ..execute(
      'INSERT INTO workflow_version (id, workflow_id, version, yaml) '
      "VALUES ('wfv_e2e', 'wf_e2e', 1, '')",
    );
}

void _printLogs(String directory) {
  final logs = Directory(directory);
  if (!logs.existsSync()) return;
  for (final file in logs.listSync().whereType<File>()) {
    _log('--- ${p.basename(file.path)}');
    for (final line in file.readAsLinesSync()) {
      final json = jsonDecode(line) as Map<String, dynamic>;
      _log('${json['text']}');
    }
  }
}

void _printBuildTail(String directory) {
  final log = Directory(directory)
      .listSync()
      .whereType<File>()
      .where((file) => p.basename(file.path).contains('build.android'))
      .firstOrNull;
  if (log == null) return;
  final lines = log.readAsLinesSync();
  for (final line in lines.skip(lines.length > 4 ? lines.length - 4 : 0)) {
    _log('flutter: ${(jsonDecode(line) as Map<String, dynamic>)['text']}');
  }
}

void _log(String message) => stderr.writeln('e2e: $message');

/// An SDK that is installed already, used for every version.
class _PreinstalledFlutter implements FlutterInstaller {
  const new(this._path);

  final String _path;

  @override
  String pathFor(String version) => _path;

  @override
  Future<bool> isInstalled(String version) async => true;

  @override
  Future<void> install(String version) async {}
}

/// No secrets: the fixture is signed with the debug key and cloned from a
/// local folder, so nothing reads one. The Keychain is never touched.
class _NoSecrets implements SecretStore {
  @override
  SecretsStatus get status => SecretsStatus.unlocked;

  @override
  Stream<SecretsStatus> get statusChanges => const Stream.empty();

  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) async {}

  @override
  Future<Uint8List?> readBytes(String key) async => null;

  @override
  Future<void> writeBytes(String key, List<int> value) async {}

  @override
  Future<void> delete(String key) async {}
}

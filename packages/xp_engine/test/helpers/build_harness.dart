import 'dart:math';

import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import 'fake_build_files.dart';
import 'fake_flutter_installer.dart';

/// The commit every build test dispatches.
const buildSha = 'a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1';

String _machine(String flutter) =>
    '{"frameworkVersion": "$flutter", "dartSdkVersion": "3.13.5"}';

/// The worktree of a job that builds the app at `apps/mobile`.
const buildWorktree = ReleaseWorktree(
  path: '/work/job_1',
  mirror: GitMirror(key: '42', path: '/mirrors/42.git'),
  sha: buildSha,
  appPath: 'apps/mobile',
);

/// The app directory of [buildWorktree].
const appDirectory = '/work/job_1/apps/mobile';

/// A [StepContext] whose commands end the way the test says, and that runs
/// [onRun] while a command runs (to make the build write its files).
class BuildContext implements StepContext {
  new({this.exit = const ProcessExit(exitCode: 0), this.onRun});

  ProcessExit exit;
  void Function(ProcessCommand command)? onRun;
  final commands = <ProcessCommand>[];

  /// The define files of the secret store, by secret key.
  final defines = <String, String>{};

  /// The secret files the step wrote, by name.
  final secretFiles = <String, String>{};

  @override
  String get jobId => 'job_1';

  @override
  int get ordinal => 0;

  @override
  bool get isStopping => false;

  @override
  Future<String> readDartDefines(String secretKey) async =>
      defines[secretKey] ??
      (throw SecretStoreException('There is no secret "$secretKey".'));

  @override
  Future<String> writeSecretFile(String name, String contents) async {
    secretFiles[name] = contents;
    return '/secrets/job_1/$name';
  }

  @override
  Future<ProcessExit> run(
    ProcessCommand command, {
    void Function(OutputLine line)? onLine,
  }) async {
    commands.add(command);
    onRun?.call(command);
    return exit;
  }
}

/// Everything a build step needs, on fakes: a machine without fvm whose cache
/// holds the Flutter versions `flutterVersions` (3.47.6 by default) and has
/// neither Shorebird nor `gh`.
class BuildHarness {
  new({bool isMacOS = false, Set<String> flutterVersions = const {'3.47.6'}}) {
    runner = FakeProcessRunner((call) {
      if (call.executable.endsWith('/bin/flutter')) {
        final version = call.executable.split('/').reversed.elementAt(2);
        return ProcessOutput(exitCode: 0, stdout: _machine(version));
      }
      if (call.executable == 'xcode-select') {
        return const ProcessOutput(exitCode: 0, stdout: '/Xcode/Developer\n');
      }
      if (call.executable == 'xcodebuild') {
        return const ProcessOutput(
          exitCode: 0,
          stdout: 'Xcode 27.1\nBuild version 27A9275\n',
        );
      }
      throw ProcessStartException(call.executable, 'not found');
    });
    toolchain = BuildToolchain(
      resolver: FlutterResolver(
        runner: runner,
        installer: installer = FakeFlutterInstaller(installed: flutterVersions),
      ),
      prober: ToolProber(runner: runner, isMacOS: isMacOS),
      jobs: jobs,
    );
    recorder = ArtifactRecorder(
      store: store,
      repository: artifacts,
      clock: clock,
      random: _SequenceRandom(),
    );
  }

  late final FakeProcessRunner runner;
  late final FakeFlutterInstaller installer;
  final jobs = InMemoryJobRepository();
  final artifacts = InMemoryArtifactRepository();
  final store = InMemoryArtifactStore();
  final files = FakeBuildFiles();
  final clock = ManualClock(DateTime.utc(2026, 10, 13, 10));
  late final BuildToolchain toolchain;
  late final ArtifactRecorder recorder;

  /// Creates `job_1`, which the toolchain records versions for.
  Future<void> createJob() => jobs.create(
    JobRecord(
      id: 'job_1',
      workflowVersionId: 'wfv_1',
      projectId: 'prj_1',
      state: JobState.running,
      createdAt: clock.now(),
      startedAt: DateTime.utc(2026, 10, 13, 9, 30),
    ),
    const [],
  );
}

/// A random source that counts up, so ids are predictable.
class _SequenceRandom implements Random {
  var _next = 0;

  @override
  bool nextBool() => throw UnimplementedError();

  @override
  double nextDouble() => throw UnimplementedError();

  @override
  int nextInt(int max) => _next++ % max;
}

@Tags(['process'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xp/src/config/client_secret_store.dart';
import 'package:xp/src/runner/job/uploading_artifacts.dart';
import 'package:xp/src/runner/runner_agent.dart';
import 'package:xp/src/runner/runner_identity.dart';
import 'package:xp/src/runner/runner_paths.dart';
import 'package:xp/src/runner/runner_runtime.dart';
import 'package:xp/src/runner/runner_socket.dart';
import 'package:xp/src/runner/secrets/secret_area.dart';
import 'package:xp/src/version.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/fake_runner_engine.dart';

/// The real runner (the process supervisor, the step runner, the secret
/// folder, the connection) against a fake engine that plays the other side of
/// the protocol on a loopback port.
void main() {
  late Directory directory;
  late RunnerPaths paths;
  late FakeRunnerEngine engine;
  late List<String> said;
  late RunnerHost host;

  RunnerSetup setup({int? slots, bool oneShot = false}) => RunnerSetup(
    paths: paths,
    enrollment: RunnerEnrollment(
      identity: RunnerIdentity(
        engine: engine.url,
        runnerId: 'rnr_1',
        name: 'mac-mini',
      ),
      credential: engine.credential,
    ),
    host: host,
    log: said.add,
    clientFactory: (connection) =>
        XpClient(baseUrl: connection.url, token: connection.token),
    slots: slots,
    oneShot: oneShot,
  );

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('xp_runtime_');
    addTearDown(() => directory.deleteSync(recursive: true));
    paths = RunnerPaths(p.join(directory.path, 'runner'));
    addTearDown(() {
      // The secret folder of a Linux runner is in /dev/shm, not in `directory`.
      final places = SecretLocations.choose(
        operatingSystem: Platform.isMacOS ? 'macos' : 'linux',
        environment: Platform.environment,
        paths: paths,
      );
      for (final place in places.all) {
        final folder = Directory(place);
        if (folder.existsSync()) folder.deleteSync(recursive: true);
      }
    });
    engine = await FakeRunnerEngine.start();
    addTearDown(engine.close);
    said = [];
    host = RunnerHost(
      operatingSystem: Platform.isMacOS ? 'macos' : 'linux',
      cores: 8,
      pid: pid,
      environment: {...Platform.environment, 'HOME': directory.path},
      runner: const IoProcessRunner(),
    );
  });

  Map<String, dynamic> commandInput(
    String script, {
    Map<String, String>? env,
  }) => {
    'executable': 'sh',
    'arguments': ['-c', script],
    'environment': <String, String>{},
    'passThroughEnvironment': <String>[],
    'secretEnvironment': env ?? <String, String>{},
    'secretFiles': <String, String>{},
    'sideEffect': false,
  };

  LeaseOfferFrame offer(
    Map<String, dynamic> input, {
    List<String> secrets = const [],
  }) => LeaseOfferFrame(
    leaseId: 'lse_1',
    jobId: 'job_1',
    projectId: 'prj_1',
    stage: 0,
    capabilities: const [],
    expiresAt: DateTime.utc(2030),
    steps: [
      LeaseStep(
        ordinal: 0,
        kind: 'command',
        sideEffect: false,
        state: StepState.pending,
        attempts: 0,
        input: input,
      ),
    ],
    secrets: secrets,
  );

  test('says hello, answers the probe, runs a job and drains', () async {
    // What an earlier run left behind.
    final stale = File(p.join(paths.fallbackSecrets, 'job_old', 'delivered-x'))
      ..createSync(recursive: true)
      ..writeAsStringSync('old secret');
    final runner = await buildRunner(setup(slots: 2));
    final running = runner.run();
    final session = await engine.connection;

    session.send(
      WelcomeFrame(
        runnerId: 'rnr_1',
        engineVersion: packageVersion,
        apiVersion: apiVersion,
        heartbeatSeconds: 1,
      ),
    );
    final hello = await session.next<HelloFrame>();
    expect(hello.version, packageVersion);
    expect(hello.os, host.operatingSystem);
    expect(hello.arch, isNotEmpty);
    expect(hello.cores, 8);
    expect(hello.maxJobs, 2);
    expect(hello.leases, isEmpty);

    // The probe runs the engine's commands for real, except `swift`: on a CI
    // runner it can hang until the probe's 30 s timeout, as long as this test
    // waits for the result.
    session.send(
      ProbeFrame(
        probeId: 'prb_1',
        commands: [
          for (final command in const RunnerProbe().commands)
            if (command.id != 'swift') command,
        ],
      ),
    );
    final probed = await session.next<ProbeResultFrame>();
    final os = probed.results.firstWhere((r) => r.id == 'os');
    expect(os.stdout.trim(), Platform.isMacOS ? 'Darwin' : 'Linux');
    expect(probed.results.firstWhere((r) => r.id == 'git').succeeded, isTrue);
    expect(
      const RunnerProbe().evaluate(probed.results).capabilities,
      contains(Capability.flutter),
    );
    await session.next<HeartbeatFrame>();

    // A job with a secret: asked of the engine, given to the process, hidden
    // in the output, wiped at the end.
    session.send(
      offer(
        commandInput(r'echo "token=$TOKEN"; echo plain', env: {'TOKEN': 'sk'}),
        secrets: ['sk'],
      ),
    );
    final accept = await session.next<LeaseAcceptFrame>();
    expect(accept.leaseId, 'lse_1');
    final asked = await session.next<SecretRequestFrame>();
    expect(asked.key, 'sk');
    session.send(
      SecretValueFrame(
        jobId: 'job_1',
        leaseId: 'lse_1',
        key: 'sk',
        value: base64Encode(utf8.encode('hunter2hunter2')),
      ),
    );
    final done = await session.next<JobDoneFrame>();
    expect(done.state, JobState.succeeded, reason: done.message);
    expect(done.lastChunk, 1);
    final chunk = await session.next<LogChunkFrame>();
    expect([for (final line in chunk.lines) line.text], ['token=***', 'plain']);
    final steps = [
      for (final frame in [
        await session.next<StepStateFrame>(),
        await session.next<StepStateFrame>(),
      ])
        frame.state,
    ];
    expect(steps, [StepState.running, StepState.succeeded]);
    expect(
      stale.existsSync(),
      isFalse,
      reason: 'wiped when the runner started',
    );
    expect(
      Directory(p.join(paths.fallbackSecrets, 'job_1')).existsSync(),
      isFalse,
      reason: 'wiped when the job ended',
    );

    session.send(
      const DoneAckFrame(
        jobId: 'job_1',
        leaseId: 'lse_1',
        state: JobState.succeeded,
      ),
    );
    runner.drain();
    expect(await running, AgentExit.drained);
    expect(said.first, contains('Cleaned up after an earlier run'));
  });

  test(
    'probes the omarchy-apple-dev checkout XP_IOS_LINUX_DIR names',
    () async {
      host = RunnerHost(
        operatingSystem: host.operatingSystem,
        cores: 8,
        pid: pid,
        environment: {
          ...host.environment,
          iosLinuxDirectoryVariable: directory.path,
        },
        runner: const IoProcessRunner(),
      );
      final runner = await buildRunner(setup());
      final running = runner.run();
      final session = await engine.connection;
      session.send(
        WelcomeFrame(
          runnerId: 'rnr_1',
          engineVersion: packageVersion,
          apiVersion: apiVersion,
        ),
      );
      await session.next<HelloFrame>();

      session.send(
        const ProbeFrame(
          probeId: 'prb_1',
          commands: [
            ProbeCommand(
              id: 'git',
              executable: 'git',
              arguments: ['--version'],
            ),
          ],
        ),
      );
      final probed = await session.next<ProbeResultFrame>();

      expect(probed.iosLinuxDir, directory.path);
      expect(probed.results.map((result) => result.id), [
        'git',
        'ios_linux_commit',
        'ios_linux_sdk',
        'ios_linux_tools',
      ]);
      await runner.stop();
      await running;
    },
  );

  test('runs one job and exits when it is one-shot', () async {
    final runner = await buildRunner(setup(oneShot: true));
    final running = runner.run();
    final session = await engine.connection;
    session.send(
      WelcomeFrame(
        runnerId: 'rnr_1',
        engineVersion: packageVersion,
        apiVersion: apiVersion,
      ),
    );
    final hello = await session.next<HelloFrame>();
    expect(hello.maxJobs, isNull);

    session.send(offer(commandInput('exit 3')));
    await session.next<DrainFrame>();
    final done = await session.next<JobDoneFrame>();
    expect(done.state, JobState.failed);
    expect(done.message, contains('Step 0 (command) failed'));
    session.send(
      const DoneAckFrame(
        jobId: 'job_1',
        leaseId: 'lse_1',
        state: JobState.failed,
      ),
    );

    expect(await running, AgentExit.oneShotDone);
  });

  test('a one-shot runner does not update, whatever the engine runs', () async {
    final runner = await buildRunner(setup(oneShot: true));
    final running = runner.run();
    final session = await engine.connection;
    session.send(
      WelcomeFrame(
        runnerId: 'rnr_1',
        engineVersion: '9.9.9',
        apiVersion: apiVersion,
      ),
    );

    final hello = await session.next<HelloFrame>();

    expect(hello.draining, isFalse);
    expect(engine.bundleRequests, isEmpty);
    runner.drain();
    expect(await running, AgentExit.drained);
  });

  test(
    'drains instead of restarting when told to stop during the update',
    () async {
      // The engine has no bundle: the update fails, and the runner, which was
      // told to drain meanwhile, ends.
      final runner = await buildRunner(setup());
      final running = runner.run();
      final session = await engine.connection;
      session.send(
        WelcomeFrame(
          runnerId: 'rnr_1',
          engineVersion: '9.9.9',
          apiVersion: apiVersion,
        ),
      );
      await session.next<HelloFrame>();
      runner.drain();

      expect(await running, AgentExit.drained);
    },
  );

  test('the bundle that runs is the folder of bin/xp', () {
    RunnerHost on(String executable) => RunnerHost(
      operatingSystem: 'linux',
      cores: 1,
      pid: 1,
      environment: const {},
      runner: const IoProcessRunner(),
      executable: executable,
    );

    expect(on('/opt/xpath/xp/bin/xp').bundle, '/opt/xpath/xp');
    expect(on('/sdk/bin/dart').bundle, isNull);
    expect(on('/opt/xp').bundle, isNull);
    expect(on('').bundle, isNull);
  });

  test('stops a job that is cancelled, with its process group', () async {
    final marker = File(p.join(directory.path, 'marker'));
    final runner = await buildRunner(setup());
    final running = runner.run();
    final session = await engine.connection;
    session.send(
      WelcomeFrame(
        runnerId: 'rnr_1',
        engineVersion: packageVersion,
        apiVersion: apiVersion,
      ),
    );
    await session.next<HelloFrame>();
    session.send(
      offer(commandInput('sleep 300 & echo \$! > ${marker.path}; wait')),
    );
    await session.next<LeaseAcceptFrame>();
    while (!marker.existsSync() || marker.readAsStringSync().trim().isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    final child = int.parse(marker.readAsStringSync().trim());
    expect(Process.killPid(child, ProcessSignal.sigcont), isTrue);

    session.send(
      const CancelFrame(jobId: 'job_1', leaseId: 'lse_1', reason: 'Cancelled.'),
    );
    for (
      var i = 0;
      i < 100 && Process.killPid(child, ProcessSignal.sigcont);
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    expect(
      Process.killPid(child, ProcessSignal.sigcont),
      isFalse,
      reason: 'the grandchild died with its group',
    );
    await runner.stop();
    expect(await running, AgentExit.stopped);
  });

  test(
    'warns when the machine cannot be kept awake, and runs all the same',
    () async {
      host = RunnerHost(
        operatingSystem: host.operatingSystem,
        cores: 8,
        pid: pid,
        environment: host.environment,
        runner: _NoProcesses(),
      );
      final runner = await buildRunner(setup());
      final running = runner.run();
      final session = await engine.connection;
      session.send(
        WelcomeFrame(
          runnerId: 'rnr_1',
          engineVersion: packageVersion,
          apiVersion: apiVersion,
        ),
      );
      final hello = await session.next<HelloFrame>();
      expect(hello.arch, 'unknown', reason: 'uname could not be run');

      session.send(offer(commandInput('echo ok')));
      final done = await session.next<JobDoneFrame>();

      expect(done.state, JobState.succeeded, reason: done.message);
      expect(
        said.where((m) => m.startsWith('Warning: Cannot keep')),
        isNotEmpty,
      );
      await runner.stop();
      await running;
    },
  );

  test('knows why the engine closed the connection', () async {
    final client = XpClient(baseUrl: engine.url, token: engine.credential);
    addTearDown(client.close);
    final socket = ChannelRunnerSocket(await client.connectRunner());
    final session = await engine.connection;
    final frames = <String>[];
    final closed = socket.frames.listen(frames.add).asFuture<void>();

    session.send(const FaultFrame(code: 'x', message: 'y'));
    await session.close(runnerRevokedCloseCode);
    await closed;

    expect(frames, hasLength(1));
    expect(socket.closeCode, runnerRevokedCloseCode);
    socket.send('{"type":"heartbeat","leases":[]}');
    await socket.close(1000, 'bye');
  });

  test('fails to build without perl', () async {
    host = RunnerHost(
      operatingSystem: host.operatingSystem,
      cores: 8,
      pid: pid,
      environment: {'PATH': directory.path},
      runner: const IoProcessRunner(),
    );

    await expectLater(buildRunner(setup()), throwsA(isA<ToolchainException>()));
  });

  group('the upload of artifacts', () {
    test('sends the file with its digest and the lease', () async {
      final client = XpClient(baseUrl: engine.url, token: engine.credential);
      addTearDown(client.close);

      await uploadThrough(client)(
        jobId: 'job_1',
        leaseId: 'lse_1',
        name: 'app.apk',
        kind: ArtifactKind.apk,
        content: () => Stream.value([1, 2, 3]),
        size: 3,
        sha256: 'abc',
      );

      final upload = engine.artifacts.single;
      expect(upload.jobId, 'job_1');
      expect(upload.name, 'app.apk');
      expect(upload.query, {'kind': 'apk'});
      expect(upload.headers['x-lease-id'], 'lse_1');
      expect(upload.headers['x-content-sha256'], 'abc');
      expect(upload.bytes, [1, 2, 3]);
      expect(upload.headers['authorization'], 'Bearer ${engine.credential}');
    });

    test('is refused when the lease is not held', () async {
      engine.uploadStatus = 409;
      final client = XpClient(baseUrl: engine.url, token: engine.credential);
      addTearDown(client.close);

      await expectLater(
        uploadThrough(client)(
          jobId: 'job_1',
          leaseId: 'lse_1',
          name: 'app.apk',
          kind: ArtifactKind.apk,
          content: () => Stream.value([1]),
          size: 1,
          sha256: 'abc',
        ),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('the host', () {
    test(
      'keeps the credential in the Keychain on a Mac and in a file elsewhere',
      () {
        expect(
          const RunnerHost(
            operatingSystem: 'macos',
            cores: 1,
            pid: 1,
            environment: {},
            runner: IoProcessRunner(),
          ).credentials(paths),
          isA<SecretStore>(),
        );
        final file = const RunnerHost(
          operatingSystem: 'macos',
          cores: 1,
          pid: 1,
          environment: {fileSecretsVariable: '1'},
          runner: IoProcessRunner(),
        ).credentials(paths);
        final linux = const RunnerHost(
          operatingSystem: 'linux',
          cores: 1,
          pid: 1,
          environment: {},
          runner: IoProcessRunner(),
        ).credentials(paths);

        expect(file.runtimeType, linux.runtimeType);
        expect(file.runtimeType.toString(), 'EncryptedFileSecretStore');
      },
    );

    test('knows the real machine', () {
      final real = RunnerHost.system({'HOME': '/home/me'});

      expect(real.operatingSystem, Platform.operatingSystem);
      expect(real.cores, Platform.numberOfProcessors);
      expect(real.pid, pid);
      expect(real.home, '/home/me');
      expect(RunnerHost.system(const {}).home, isEmpty);
      expect(real.isMacOS, Platform.isMacOS);
    });

    test('reads the omarchy-apple-dev checkout from XP_IOS_LINUX_DIR', () {
      expect(
        RunnerHost.system({iosLinuxDirectoryVariable: '/srv/omarchy'})
            .iosLinuxDirectory,
        '/srv/omarchy',
      );
      expect(
        RunnerHost.system({iosLinuxDirectoryVariable: ''}).iosLinuxDirectory,
        isNull,
      );
      expect(RunnerHost.system(const {}).iosLinuxDirectory, isNull);
    });
  });
}

/// Starts no process: not even a helper that keeps the machine awake.
class _NoProcesses implements ProcessRunner {
  @override
  Future<RunningProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async => throw ProcessStartException(executable, 'not installed');
}

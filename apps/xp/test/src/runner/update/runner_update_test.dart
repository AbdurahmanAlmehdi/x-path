@Tags(['process'])
library;

import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xp/src/context.dart';
import 'package:xp/src/exit_codes.dart';
import 'package:xp/src/runner/runner_command.dart';
import 'package:xp/src/runner/runner_identity.dart';
import 'package:xp/src/runner/runner_paths.dart';
import 'package:xp/src/runner/runner_runtime.dart';
import 'package:xp/src/runner/secrets/secret_area.dart';
import 'package:xp/src/runner/update/restarter.dart';
import 'package:xp/src/runner/update/runner_versions.dart';
import 'package:xp/src/runner/update/update_journal.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';

import '../../../helpers/bundle_fixtures.dart';
import '../../../helpers/fake_runner_engine.dart';
import '../../../helpers/memory_secret_store.dart';
import '../../../helpers/test_env.dart';

/// Phase 14c: a runner whose version is not the engine's finishes its job,
/// then downloads the engine's bundle, checks it, switches `current` to it and
/// starts again as the new version, which the engine welcomes (D-24).
///
/// The runner is the real one (`buildRunner`, the real `tar`, a real bundle
/// folder with a `bin/xp` that prints its version) against a fake engine on a
/// loopback port. The two versions run in this process: the version a
/// `RunnerSetup` carries is what the runner reports, and the [Restarter] that
/// would replace the process starts the next version here instead.
void main() {
  const oldVersion = '0.0.1';
  const newVersion = '0.0.2';
  late Directory directory;
  late RunnerPaths paths;
  late FakeRunnerEngine engine;
  late TestEnv env;
  late XpContext context;
  late RunnerHost host;
  late MemorySecretStore credentials;
  late List<(String, List<String>)> launches;
  late List<StreamController<ProcessSignal>> signals;
  late File gate;

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('xp_update_');
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
      directory.deleteSync(recursive: true);
    });
    engine = await FakeRunnerEngine.start();
    addTearDown(engine.close);
    env = TestEnv();
    addTearDown(env.dispose);
    // The commands dial the fake engine with the real client.
    context = XpContext(
      logger: env.logger,
      config: env.config,
      environment: env.environment,
      clientFactory: (connection) =>
          XpClient(baseUrl: connection.url, token: connection.token),
      updateCheck: env.update,
      stdin: env.stdin.stream,
      stdout: env.stdout,
    );
    credentials = MemorySecretStore();
    final running = writeBundle(directory, version: oldVersion);
    host = RunnerHost(
      operatingSystem: Platform.isMacOS ? 'macos' : 'linux',
      cores: 4,
      pid: pid,
      environment: {...Platform.environment, 'HOME': directory.path},
      runner: const IoProcessRunner(),
      openCredentials: (_) => credentials,
      executable: p.join(running.path, 'bin', 'xp'),
    );
    await RunnerEnrollments(paths, credentials).write(
      RunnerEnrollment(
        identity: RunnerIdentity(
          engine: engine.url,
          runnerId: 'rnr_1',
          name: 'mac-mini',
        ),
        credential: engine.credential,
      ),
    );
    launches = [];
    signals = [];
    gate = File(p.join(directory.path, 'gate'));
    engine.bundle = tarBundle(writeBundle(directory, version: newVersion));
  });

  tearDown(() async {
    for (final controller in signals) {
      await controller.close();
    }
  });

  /// `xp runner start` as [version], the way a process of that version would
  /// run it. [restarter] starts what comes after an update; by default the
  /// new version is started in this process.
  Future<int> start(String version, {Restarter? restarter}) {
    final controller = StreamController<ProcessSignal>.broadcast();
    signals.add(controller);
    final commands = CommandRunner<int>('xp', 'test')
      ..addCommand(
        runnerCommand(
          context,
          host: host,
          signals: controller.stream,
          // The restarter that would replace the process starts the next
          // version in this one.
          restarter:
              restarter ??
              Restarter(
                managed: false,
                launch: (executable, arguments) {
                  launches.add((executable, arguments));
                  return start(newVersion);
                },
              ),
          build: (setup) => buildRunner(
            RunnerSetup(
              paths: setup.paths,
              enrollment: setup.enrollment,
              host: setup.host,
              log: setup.log,
              clientFactory: setup.clientFactory,
              slots: setup.slots,
              oneShot: setup.oneShot,
              version: version,
            ),
          ),
        ),
      );
    return commands
        .run(['runner', 'start', '--data-dir', paths.root])
        .then((code) => code ?? 0);
  }

  void drain() => signals.last.add(ProcessSignal.sigterm);

  Map<String, dynamic> waitForGate() => {
    'executable': 'sh',
    'arguments': [
      '-c',
      'while [ ! -f "${gate.path}" ]; do sleep 0.05; done; echo finished',
    ],
    'environment': <String, String>{},
    'passThroughEnvironment': <String>[],
    'secretEnvironment': <String, String>{},
    'secretFiles': <String, String>{},
    'sideEffect': false,
  };

  LeaseOfferFrame offerOf(
    String jobId,
    String leaseId,
    Map<String, dynamic> input,
  ) => LeaseOfferFrame(
    leaseId: leaseId,
    jobId: jobId,
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
  );

  WelcomeFrame welcomeOf(String engineVersion) => WelcomeFrame(
    runnerId: 'rnr_1',
    engineVersion: engineVersion,
    apiVersion: apiVersion,
  );

  String? currentVersion() => RunnerVersions(paths).currentVersion();

  test('an outdated runner updates after its current job, restarts as the new '
      'version and reconnects with it', () async {
    final running = start(oldVersion);

    // The runner took a job under the engine of its own version ...
    final first = await engine.connection;
    first.send(welcomeOf(oldVersion));
    expect((await first.next<HelloFrame>()).version, oldVersion);
    first.send(offerOf('job_1', 'lse_1', waitForGate()));
    await first.next<LeaseAcceptFrame>();
    // ... and the engine was upgraded meanwhile: the connection drops, and
    // the runner comes back to an engine of another version.
    await first.close(1001);
    final second = await engine.connection;
    second.send(welcomeOf(newVersion));

    final hello = await second.next<HelloFrame>();
    expect(hello.version, oldVersion);
    expect(hello.draining, isTrue, reason: 'no new jobs while it updates');
    expect(hello.leases.single.jobId, 'job_1', reason: 'the job still runs');
    second.send(offerOf('job_2', 'lse_2', waitForGate()));
    expect((await second.next<LeaseRejectFrame>()).reason, 'updating');

    // The job is not touched: nothing is downloaded and nothing switches
    // while it runs.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(engine.bundleRequests, isEmpty);
    expect(launches, isEmpty);
    expect(currentVersion(), isNull);

    // The job ends ...
    gate.writeAsStringSync('go');
    final done = await second.next<JobDoneFrame>();
    expect(done.state, JobState.succeeded, reason: done.message);
    expect(engine.bundleRequests, isEmpty, reason: 'the engine has not acked');
    second.send(
      const DoneAckFrame(
        jobId: 'job_1',
        leaseId: 'lse_1',
        state: JobState.succeeded,
      ),
    );

    // ... and then the runner restarts as the new version, which the engine
    // welcomes.
    final third = await engine.connection;
    expect(engine.bundleRequests, hasLength(1));
    expect(
      engine.bundleRequests.single.authorization,
      'Bearer ${engine.credential}',
    );
    expect(engine.bundleRequests.single.os, host.operatingSystem);
    expect(engine.bundleRequests.single.arch, isNotEmpty);
    expect(launches, hasLength(1));
    expect(launches.single.$1, paths.currentExecutable);
    expect(launches.single.$2, ['runner', 'start', '--data-dir', paths.root]);
    expect(currentVersion(), newVersion);
    expect(
      File(paths.currentExecutable).readAsStringSync(),
      contains(newVersion),
    );
    third.send(welcomeOf(newVersion));
    final again = await third.next<HelloFrame>();
    expect(again.version, newVersion);
    expect(again.draining, isFalse);
    expect(again.leases, isEmpty);

    // The new version takes jobs, and is proven: only it and the version
    // before stay, and no update is left waiting.
    third.send(offerOf('job_3', 'lse_3', waitForGate()));
    expect((await third.next<LeaseAcceptFrame>()).jobId, 'job_3');
    final journal = UpdateJournal(paths.updateState);
    expect(journal.pending, isNull);
    expect(
      Directory(paths.versions)
          .listSync()
          .map((e) => p.basename(e.path))
          .toSet(),
      {oldVersion, newVersion},
    );
    expect(
      env.logger.infos,
      contains('Updated from $oldVersion to $newVersion.'),
    );

    // (The gate is open: the job ends at once.)
    expect((await third.next<JobDoneFrame>()).state, JobState.succeeded);
    third.send(
      const DoneAckFrame(
        jobId: 'job_3',
        leaseId: 'lse_3',
        state: JobState.succeeded,
      ),
    );
    drain();
    expect(await running, XpExit.ok);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a bundle with the wrong digest is not switched to', () async {
    engine.bundleSha256 = 'b' * 64;
    final running = start(oldVersion);
    final first = await engine.connection;
    first.send(welcomeOf(newVersion));
    expect((await first.next<HelloFrame>()).draining, isTrue);

    // Nothing runs: the runner tries at once, fails, and goes on as it was.
    final second = await engine.connection;
    expect(engine.bundleRequests, hasLength(1));
    second.send(welcomeOf(newVersion));
    final hello = await second.next<HelloFrame>();
    expect(hello.version, oldVersion);
    expect(hello.draining, isFalse, reason: 'it gave up on this version');
    second.send(offerOf('job_1', 'lse_1', waitForGate()));
    expect((await second.next<LeaseAcceptFrame>()).jobId, 'job_1');

    expect(launches, isEmpty);
    expect(currentVersion(), isNull);
    expect(Directory(paths.versions).existsSync(), isFalse);
    expect(UpdateJournal(paths.updateState).pending, isNull);
    expect(
      env.logger.infos.join('\n'),
      allOf(
        contains('Cannot update to version $newVersion'),
        contains('not what the engine announced'),
        contains('stays on $oldVersion'),
      ),
    );

    gate.writeAsStringSync('go');
    await second.next<JobDoneFrame>();
    second.send(
      const DoneAckFrame(
        jobId: 'job_1',
        leaseId: 'lse_1',
        state: JobState.succeeded,
      ),
    );
    drain();
    expect(await running, XpExit.ok);
  });

  test('an engine without a bundle leaves the runner as it was', () async {
    engine.bundle = null;
    final running = start(oldVersion);
    final first = await engine.connection;
    first.send(welcomeOf(newVersion));

    final second = await engine.connection;
    second.send(welcomeOf(newVersion));
    expect((await second.next<HelloFrame>()).draining, isFalse);

    expect(launches, isEmpty);
    expect(
      env.logger.infos.join('\n'),
      contains('no runner bundle for this machine'),
    );
    drain();
    expect(await running, XpExit.ok);
  });

  test(
    'a new version that fails to start is rolled back to the one before',
    () async {
      // Under a service manager the runner exits with the restart code and
      // the manager starts `current/bin/xp` again: this test is the manager.
      const managed = Restarter(managed: true);

      // The old version updates and asks to be started again.
      final updating = start(oldVersion, restarter: managed);
      final first = await engine.connection;
      first.send(welcomeOf(newVersion));
      await first.next<HelloFrame>();
      expect(await updating, XpExit.restart);
      expect(currentVersion(), newVersion);
      expect(UpdateJournal(paths.updateState).pending!.starts, 0);

      // The new version starts and goes away again before the engine has
      // welcomed it, as often as it may.
      for (var attempt = 1; attempt <= maxUnconfirmedStarts; attempt++) {
        final run = start(newVersion, restarter: managed);
        final connected = await engine.connection;
        drain();
        // The runner looks at its state when a frame arrives.
        connected.send(const HeartbeatAckFrame());
        await run;
        expect(UpdateJournal(paths.updateState).pending!.starts, attempt);
        expect(currentVersion(), newVersion);
      }

      // The next start goes back, before it does anything else.
      expect(await start(newVersion, restarter: managed), XpExit.restart);
      expect(currentVersion(), oldVersion);
      final journal = UpdateJournal(paths.updateState);
      expect(journal.pending, isNull);
      expect(journal.blocked, newVersion);
      expect(
        env.logger.infos.join('\n'),
        allOf(
          contains('going back to $oldVersion'),
          contains('does not update to $newVersion again'),
        ),
      );

      // The old version runs again; the engine still says the new version,
      // and the runner does not try it again.
      final back = start(oldVersion, restarter: managed);
      final session = await engine.connection;
      session.send(welcomeOf(newVersion));
      final hello = await session.next<HelloFrame>();
      expect(hello.version, oldVersion);
      expect(hello.draining, isFalse);
      expect(
        env.logger.infos.join('\n'),
        contains("Not updating to the engine's version $newVersion"),
      );
      expect(
        engine.bundleRequests,
        hasLength(1),
        reason: 'only the first time',
      );
      drain();
      expect(await back, XpExit.ok);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

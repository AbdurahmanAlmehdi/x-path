import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:xp/src/runner/runner_agent.dart';
import 'package:xp/src/runner/runner_command.dart';
import 'package:xp/src/runner/runner_identity.dart';
import 'package:xp/src/runner/runner_paths.dart';
import 'package:xp/src/runner/runner_runtime.dart';
import 'package:xp/src/runner/update/restarter.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/memory_secret_store.dart';
import '../../helpers/test_env.dart';

class _FakeRunnerProcess implements RunnerProcess {
  new(this.exit);

  final Future<AgentExit> Function(_FakeRunnerProcess self) exit;
  int drains = 0;
  int stops = 0;
  final stopped = Completer<void>();

  @override
  Future<AgentExit> run() => exit(this);

  @override
  void drain() => drains++;

  @override
  Future<void> stop() async {
    stops++;
    if (!stopped.isCompleted) stopped.complete();
  }
}

void main() {
  late TestEnv env;
  late Directory directory;
  late RunnerPaths paths;
  late MemorySecretStore credentials;
  late RunnerHost host;
  late RunnerSetup? built;
  late _FakeRunnerProcess process;
  late StreamController<ProcessSignal> signals;
  late CommandRunner<int> commands;
  Exception? buildFails;
  late List<(String, List<String>)> restarts;

  final paired = PairRunnerResponse(
    runner: Runner(
      id: 'rnr_1',
      name: 'mac-mini',
      status: RunnerStatus.offline,
      capabilities: const [],
      slots: 1,
      jobIds: const [],
      createdAt: DateTime.utc(2026, 10, 14),
    ),
    token: 'xpr_credential',
  );

  setUp(() {
    registerFallbackValue(const ProjectGates({}));
    env = TestEnv();
    directory = Directory.systemTemp.createTempSync('xp_runner_command_');
    addTearDown(() {
      env.dispose();
      directory.deleteSync(recursive: true);
    });
    paths = RunnerPaths('${directory.path}/runner');
    credentials = MemorySecretStore();
    host = RunnerHost(
      operatingSystem: 'linux',
      cores: 8,
      pid: 1,
      environment: {'HOME': directory.path},
      runner: FakeProcessRunner((call) => const ProcessOutput(exitCode: 0)),
      openCredentials: (_) => credentials,
    );
    built = null;
    buildFails = null;
    process = _FakeRunnerProcess((_) async => AgentExit.drained);
    signals = StreamController<ProcessSignal>.broadcast();
    restarts = [];
    commands = CommandRunner<int>('xp', 'test')
      ..addCommand(
        runnerCommand(
          env.context,
          host: host,
          signals: signals.stream,
          // Never starts a program: the new version is only recorded.
          restarter: Restarter(
            managed: false,
            launch: (executable, arguments) async {
              restarts.add((executable, arguments));
              return 42;
            },
          ),
          build: (setup) async {
            built = setup;
            if (buildFails case final error?) throw error;
            return process;
          },
        ),
      );
  });

  tearDown(() => signals.close());

  /// Runs `xp runner <arguments>` the way `XpCommandRunner` does: a usage
  /// error is exit code 64.
  Future<int> run(List<String> arguments) async {
    try {
      return await commands.run(['runner', ...arguments]) ?? 0;
    } on UsageException {
      return 64;
    }
  }

  Future<void> enroll() => RunnerEnrollments(paths, credentials).write(
    RunnerEnrollment(
      identity: RunnerIdentity(
        engine: Uri.parse('http://engine:7480'),
        runnerId: 'rnr_1',
        name: 'mac-mini',
      ),
      credential: 'xpr_credential',
    ),
  );

  test('is a command of xp', () async {
    expect(env.runner.commands.keys, contains('runner'));
    expect(env.runner.commands['runner']!.subcommands.keys, [
      'pair',
      'start',
      'install-service',
      'uninstall-service',
      'service-status',
    ]);
    expect(await env.run(['runner', '--help']), 0);
  });

  group('pair', () {
    List<String> pairArguments([List<String> more = const []]) => [
      'pair',
      '--engine',
      'http://engine:7480',
      '--token',
      'xpp_pairing',
      '--data-dir',
      paths.root,
      ...more,
    ];

    setUp(() {
      when(() => env.client.version()).thenAnswer(
        (_) async => VersionResponse(version: '1.0.0', apiVersion: apiVersion),
      );
      when(() => env.client.pairRunner(any())).thenAnswer((_) async => paired);
    });

    test('exchanges the pairing token and keeps the credential', () async {
      expect(await run(pairArguments()), 0);

      verify(() => env.client.pairRunner('xpp_pairing')).called(1);
      final enrollment = (await RunnerEnrollments(paths, credentials).read())!;
      expect(enrollment.credential, 'xpr_credential');
      expect(enrollment.identity.runnerId, 'rnr_1');
      expect(enrollment.identity.name, 'mac-mini');
      expect(enrollment.identity.engine, Uri.parse('http://engine:7480'));
      expect(env.logger.out, contains('Paired as the runner "mac-mini"'));
      expect(env.logger.out, contains('rnr_1'));
      expect(env.logger.out, contains('xp runner start'));
      expect(env.logger.out, isNot(contains('xpr_credential')));
      expect(env.logger.out, isNot(contains('xpp_pairing')));
      expect(env.client.closed, 1);
    });

    test('dials the engine without a token of its own', () async {
      await run(pairArguments());

      expect(env.connections.single.url, Uri.parse('http://engine:7480'));
      expect(env.connections.single.token, isEmpty);
    });

    test('takes a bare host and port for an engine', () async {
      expect(
        await run([
          'pair',
          '--engine',
          'engine:7480',
          '--token',
          'xpp_pairing',
          '--data-dir',
          paths.root,
        ]),
        0,
      );

      expect(env.connections.single.url, Uri.parse('http://engine:7480'));
    });

    test('keeps its files in the default data directory', () async {
      host = RunnerHost(
        operatingSystem: 'linux',
        cores: 8,
        pid: 1,
        environment: {'HOME': directory.path},
        runner: FakeProcessRunner((call) => const ProcessOutput(exitCode: 0)),
        openCredentials: (_) => credentials,
      );
      commands = CommandRunner<int>('xp', 'test')
        ..addCommand(runnerCommand(env.context, host: host));

      expect(
        await run([
          'pair',
          '--engine',
          'http://engine:7480',
          '--token',
          'xpp_pairing',
        ]),
        0,
      );

      expect(
        File('${directory.path}/.local/share/xpath/runner/runner.json')
            .existsSync(),
        isTrue,
      );
    });

    test('needs the engine and the token', () async {
      expect(await run(['pair', '--token', 't']), 64);
      expect(await run(['pair', '--engine', 'http://engine:7480']), 64);
      expect(await run([...pairArguments(), 'extra']), 64);
      verifyNever(() => env.client.pairRunner(any()));
    });

    test('refuses an engine address that is not one', () async {
      expect(
        await run([
          'pair',
          '--engine',
          'ftp://engine',
          '--token',
          't',
          '--data-dir',
          paths.root,
        ]),
        64,
      );
    });

    test('does not pair twice in one data directory', () async {
      await enroll();

      expect(await run(pairArguments()), 73);

      expect(env.logger.errors.single, contains('is paired already'));
      expect(env.logger.errors.single, contains('"mac-mini"'));
      verifyNever(() => env.client.pairRunner(any()));
    });

    test('pairs again when told to', () async {
      await enroll();

      expect(await run(pairArguments(['--force'])), 0);

      verify(() => env.client.pairRunner('xpp_pairing')).called(1);
    });

    test('says when the engine speaks another API', () async {
      when(() => env.client.version()).thenAnswer(
        (_) async => const VersionResponse(version: '9.0.0', apiVersion: '9'),
      );

      expect(await run(pairArguments()), 69);

      expect(env.logger.errors.single, contains('speaks API v9'));
      verifyNever(() => env.client.pairRunner(any()));
    });

    test('says what to do about a pairing token the engine refuses', () async {
      when(() => env.client.pairRunner(any())).thenThrow(
        const ApiException(
          'Unknown, expired or used pairing token.',
          statusCode: 401,
          code: ApiErrorCode.unauthorized,
        ),
      );

      expect(await run(pairArguments()), 77);

      expect(env.logger.errors.single, contains('xp runners pair <name>'));
      expect(await RunnerEnrollments(paths, credentials).read(), isNull);
    });

    test('reports any other refusal like any command', () async {
      when(() => env.client.pairRunner(any())).thenThrow(
        const ApiException(
          'The name is taken.',
          statusCode: 409,
          code: ApiErrorCode.conflict,
        ),
      );

      expect(await run(pairArguments()), 73);

      expect(env.logger.errors.single, 'The name is taken.');
    });

    test('says when the engine cannot be reached', () async {
      when(() => env.client.version())
          .thenThrow(const ConnectionException('Connection refused.'));

      expect(await run(pairArguments()), 69);
    });

    test('warns when the engine names the runner otherwise', () async {
      expect(await run(pairArguments(['--name', 'build-box'])), 0);

      expect(
        env.logger.warnings.single,
        contains('named this runner "mac-mini"'),
      );
    });

    test('does not warn when the name is the one expected', () async {
      expect(await run(pairArguments(['--name', 'mac-mini'])), 0);

      expect(env.logger.warnings, isEmpty);
    });
  });

  group('start', () {
    setUp(enroll);

    test('says what to do when this data directory is not paired', () async {
      expect(await run(['start', '--data-dir', '${directory.path}/other']), 78);

      expect(env.logger.errors.single, contains('is not paired'));
      expect(env.logger.errors.single, contains('xp runner pair'));
      expect(built, isNull);
    });

    test('runs the runner it is given, with what the owner asked', () async {
      expect(
        await run([
          'start',
          '--data-dir',
          paths.root,
          '--slots',
          '3',
          '--one-shot',
        ]),
        0,
      );

      final setup = built!;
      expect(setup.paths.root, paths.root);
      expect(setup.enrollment.credential, 'xpr_credential');
      expect(setup.enrollment.identity.name, 'mac-mini');
      expect(setup.slots, 3);
      expect(setup.oneShot, isTrue);
      expect(setup.host, same(host));
      expect(
        env.logger.out,
        contains('Runner "mac-mini" connects to http://engine:7480'),
      );
    });

    test('leaves the slots to the engine unless it is told', () async {
      await run(['start', '--data-dir', paths.root]);

      expect(built!.slots, isNull);
      expect(built!.oneShot, isFalse);
    });

    test('refuses slots that are not a number of at least 1', () async {
      for (final bad in ['0', 'many', '-1']) {
        expect(
          await run(['start', '--data-dir', paths.root, '--slots', bad]),
          64,
          reason: bad,
        );
      }
      expect(built, isNull);
    });

    test('refuses arguments it does not know', () async {
      expect(await run(['start', '--data-dir', paths.root, 'extra']), 64);
    });

    test('exits with what the agent ended with', () async {
      for (final (exit, code) in [
        (AgentExit.drained, 0),
        (AgentExit.oneShotDone, 0),
        (AgentExit.revoked, 77),
        (AgentExit.credentialRejected, 77),
        (AgentExit.replaced, 73),
        (AgentExit.stopped, 1),
        (AgentExit.updateRequired, 1),
      ]) {
        process = _FakeRunnerProcess((_) async => exit);

        expect(
          await run(['start', '--data-dir', paths.root]),
          code,
          reason: exit.name,
        );
      }
    });

    test(
      'starts the new version after an update, with the same options',
      () async {
        process = _FakeRunnerProcess((_) async => AgentExit.updated);

        final code = await run([
          'start',
          '--data-dir',
          paths.root,
          '--slots',
          '3',
        ]);

        expect(code, 42, reason: 'the code of the new version');
        expect(restarts, hasLength(1));
        expect(restarts.single.$1, paths.currentExecutable);
        expect(restarts.single.$2, [
          'runner',
          'start',
          '--data-dir',
          paths.root,
          '--slots',
          '3',
        ]);
        expect(env.logger.out, contains('Starting the new version'));
      },
    );

    test('leaves the slots out of the restart when it had none', () async {
      process = _FakeRunnerProcess((_) async => AgentExit.updated);

      await run(['start', '--data-dir', paths.root]);

      expect(restarts.single.$2, ['runner', 'start', '--data-dir', paths.root]);
    });

    test(
      'exits for its service manager to restart it when it is managed',
      () async {
        process = _FakeRunnerProcess((_) async => AgentExit.updated);
        final managed = RunnerHost(
          operatingSystem: 'linux',
          cores: 8,
          pid: 1,
          environment: {'HOME': directory.path, runnerManagedVariable: '1'},
          runner: FakeProcessRunner((call) => const ProcessOutput(exitCode: 0)),
          openCredentials: (_) => credentials,
        );
        commands = CommandRunner<int>('xp', 'test')
          ..addCommand(
            runnerCommand(
              env.context,
              host: managed,
              signals: signals.stream,
              build: (setup) async => process,
            ),
          );

        final code = await run(['start', '--data-dir', paths.root]);

        expect(code, 75);
        expect(restarts, isEmpty);
      },
    );

    test('drains on the first signal and stops on the second', () async {
      final done = Completer<AgentExit>();
      final running = Completer<void>();
      process = _FakeRunnerProcess((_) {
        running.complete();
        return done.future;
      });
      final exited = run(['start', '--data-dir', paths.root]);
      await running.future;

      signals.add(ProcessSignal.sigterm);
      await pumpEventQueue();
      expect(process.drains, 1);
      expect(process.stops, 0);
      signals.add(ProcessSignal.sigint);
      await process.stopped.future;
      done.complete(AgentExit.stopped);

      expect(await exited, 1);
      expect(process.stops, 1);
      expect(env.logger.out, contains('Stopping now'));
    });

    test('watches the signals of the system unless told otherwise', () async {
      commands = CommandRunner<int>('xp', 'test')
        ..addCommand(
          runnerCommand(
            env.context,
            host: host,
            build: (setup) async => process,
          ),
        );

      expect(await run(['start', '--data-dir', paths.root]), 0);
    });

    test('says when perl is missing', () async {
      buildFails = const ToolchainException('perl', 'perl was not found.');

      expect(await run(['start', '--data-dir', paths.root]), 69);

      expect(env.logger.errors.single, 'perl was not found.');
    });

    test('says when the identity file is damaged', () async {
      File(paths.identityFile).writeAsStringSync('{"engine": 1}');

      expect(await run(['start', '--data-dir', paths.root]), 78);

      expect(env.logger.errors.single, contains('runner.json'));
    });

    test('says when the credential cannot be read', () async {
      credentials.failure = const SecretStoreException(
        'The Keychain is locked.',
      );

      expect(await run(['start', '--data-dir', paths.root]), 69);

      expect(env.logger.errors.single, contains('The Keychain is locked.'));
    });
  });
}

import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:xp/src/commands/xp_command.dart';
import 'package:xp/src/config/xp_config.dart';
import 'package:xp/src/context.dart';
import 'package:xp/src/exit_codes.dart';
import 'package:xp/src/runner/runner_agent.dart';
import 'package:xp/src/runner/runner_doctor.dart';
import 'package:xp/src/runner/runner_identity.dart';
import 'package:xp/src/runner/runner_options.dart';
import 'package:xp/src/runner/runner_runtime.dart';
import 'package:xp/src/runner/service/runner_service_commands.dart';
import 'package:xp/src/runner/update/restarter.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_engine/xp_engine.dart';

/// `xp runner`: this machine as a runner of an engine (D-08, D-19).
///
/// [host], [build], [signals] and [restarter] are what the commands run on and
/// with; tests pass their own.
XpGroup runnerCommand(
  XpContext context, {
  RunnerHost? host,
  RunnerBuilder build = buildRunner,
  Stream<ProcessSignal>? signals,
  Restarter? restarter,
}) {
  final machine = host ?? RunnerHost.system(context.environment);
  final restart =
      restarter ??
      Restarter(managed: machine.environment[runnerManagedVariable] == '1');
  return XpGroup(context, 'runner', 'Run jobs for an engine on this machine.', [
    RunnerPairCommand(context, machine),
    RunnerStartCommand(context, machine, build, signals, restart),
    RunnerDoctorCommand(context, machine),
    RunnerInstallServiceCommand(context, machine),
    RunnerUninstallServiceCommand(context, machine),
    RunnerServiceStatusCommand(context, machine),
  ]);
}

/// `xp runner pair --engine <url> --token <pairing token>`.
///
/// Exchanges the pairing token (`xp runners pair <name>`, made on any machine
/// with a CLI token; single use, 15 minutes) for the runner's credential and
/// keeps it in the secret store of this machine: the Keychain on macOS, an
/// encrypted file on Linux. The credential is never printed or logged.
class RunnerPairCommand extends Command<int> {
  /// Creates the command.
  new(this._context, this._host) {
    argParser
      ..addOption(
        'engine',
        abbr: 'e',
        help: 'The engine to pair with, for example https://xpath.example.com.',
        valueHelp: 'url',
      )
      ..addOption(
        'token',
        abbr: 't',
        help: 'The pairing token from `xp runners pair <name>`.',
        valueHelp: 'token',
      )
      ..addOption(
        'name',
        help:
            'The name you expect the engine to give this runner. The pairing '
            'token fixes the name; this only warns when it differs.',
        valueHelp: 'name',
      )
      ..addFlag(
        'force',
        negatable: false,
        help: 'Pair again although this data directory is paired already.',
      );
    addRunnerDataDirOption(argParser);
  }

  final XpContext _context;
  final RunnerHost _host;

  @override
  String get name => 'pair';

  @override
  String get description =>
      'Pair this machine with an engine using a pairing token.';

  @override
  String get invocation =>
      'xp runner pair --engine <url> --token <pairing token>';

  @override
  void printUsage() => _context.logger.info(usage);

  @override
  Future<int> run() => guarded(_context.logger, () async {
    final logger = _context.logger;
    final results = argResults!;
    final engine = results.option('engine');
    final token = results.option('token');
    if (engine == null) usageException('Give --engine <url>.');
    if (token == null) usageException('Give --token <pairing token>.');
    if (results.rest.isNotEmpty) {
      usageException('Unexpected "${results.rest.first}".');
    }
    final Uri url;
    try {
      url = parseEngineUrl(engine);
    } on FormatException catch (error) {
      usageException(error.message);
    }
    final paths = runnerPathsOf(results, _host);
    final enrollments = RunnerEnrollments(paths, _host.credentials(paths));
    final existing = await enrollments.read();
    if (existing != null && !results.flag('force')) {
      logger.err(
        'This data directory (${paths.root}) is paired already, as the runner '
        '"${existing.identity.name}" of ${existing.identity.engine}. Use '
        'another --data-dir, or --force to pair again.',
      );
      return XpExit.conflict;
    }
    final client = _context.clientFactory(Connection(url: url, token: ''));
    try {
      final version = await client.version();
      if (version.apiVersion != apiVersion) {
        logger.err(
          'The engine at $url speaks API v${version.apiVersion}; this xp '
          'speaks v$apiVersion. Install the xp that matches the engine.',
        );
        return XpExit.unavailable;
      }
      final PairRunnerResponse paired;
      try {
        paired = await client.pairRunner(token);
      } on ApiException catch (error) {
        if (!error.isUnauthorized) rethrow;
        logger.err(
          'The engine does not know this pairing token, or it was used or '
          'expired (it works once, for 15 minutes). Make a new one: '
          'xp runners pair <name>',
        );
        return XpExit.permission;
      }
      await enrollments.write(
        RunnerEnrollment(
          identity: RunnerIdentity(
            engine: url,
            runnerId: paired.runner.id,
            name: paired.runner.name,
          ),
          credential: paired.token,
        ),
      );
      final expected = results.option('name');
      if (expected != null && expected != paired.runner.name) {
        logger.warn(
          'The engine named this runner "${paired.runner.name}", the name its '
          'pairing token was made for, not "$expected".',
        );
      }
      logger.info(
        'Paired as the runner "${paired.runner.name}" (${paired.runner.id}) '
        'of $url. Start it: xp runner start',
      );
      return XpExit.ok;
    } finally {
      client.close();
    }
  });
}

/// `xp runner start [--slots <n>] [--one-shot] [--data-dir <dir>]`.
///
/// Connects to the engine (outbound only) and runs the jobs it leases until
/// told to stop. SIGINT or SIGTERM drains (finishes the jobs, takes none,
/// exits); a second one stops now and cancels the jobs.
///
/// When the engine runs another version, the runner finishes its jobs,
/// updates itself (`RunnerUpdater`) and starts again as the new version through
/// the [Restarter] (D-24).
class RunnerStartCommand extends Command<int> {
  /// Creates the command.
  new(this._context, this._host, this._build, this._signals, this._restarter) {
    argParser
      ..addOption(
        'slots',
        help:
            'How many jobs run at once. iOS signing jobs run one at a time '
            'whatever this is.\n'
            '(defaults to a quarter of the processor cores, at least 1)',
        valueHelp: 'n',
      )
      ..addFlag('one-shot', negatable: false, help: 'Run one job, then exit.');
    addRunnerDataDirOption(argParser);
  }

  final XpContext _context;
  final RunnerHost _host;
  final RunnerBuilder _build;
  final Stream<ProcessSignal>? _signals;
  final Restarter _restarter;

  @override
  String get name => 'start';

  @override
  String get description => 'Connect to the engine and run its jobs.';

  @override
  String get invocation => 'xp runner start [--slots <n>] [--one-shot]';

  @override
  void printUsage() => _context.logger.info(usage);

  @override
  Future<int> run() async {
    final logger = _context.logger;
    final results = argResults!;
    if (results.rest.isNotEmpty) {
      usageException('Unexpected "${results.rest.first}".');
    }
    int? slots;
    final slotsText = results.option('slots');
    if (slotsText != null) {
      slots = int.tryParse(slotsText);
      if (slots == null || slots < 1) {
        usageException('--slots must be a whole number of at least 1.');
      }
    }
    final paths = runnerPathsOf(results, _host);
    final RunnerEnrollment? enrollment;
    try {
      enrollment = await RunnerEnrollments(
        paths,
        _host.credentials(paths),
      ).read();
    } on FormatException catch (error) {
      logger.err('${paths.identityFile}: ${error.message}');
      return XpExit.config;
    } on SecretStoreException catch (error) {
      logger.err(
        'The credential of the runner cannot be read: ${error.message}',
      );
      return XpExit.unavailable;
    }
    if (enrollment == null) {
      logger.err(
        'This data directory (${paths.root}) is not paired. Run: '
        'xp runner pair --engine <url> --token <pairing token>',
      );
      return XpExit.config;
    }
    final RunnerProcess runner;
    try {
      runner = await _build(
        RunnerSetup(
          paths: paths,
          enrollment: enrollment,
          host: _host,
          log: logger.info,
          clientFactory: _context.clientFactory,
          slots: slots,
          oneShot: results.flag('one-shot'),
        ),
      );
    } on ToolchainException catch (error) {
      logger.err(error.message);
      return XpExit.unavailable;
    }
    var signalled = 0;
    final subscription = (_signals ?? _systemSignals()).listen((signal) {
      signalled++;
      if (signalled == 1) {
        runner.drain();
      } else {
        logger.info('Stopping now: the running jobs are cancelled.');
        unawaited(runner.stop());
      }
    });
    final AgentExit exit;
    try {
      final identity = enrollment.identity;
      logger.info('Runner "${identity.name}" connects to ${identity.engine}.');
      exit = await runner.run();
    } finally {
      await subscription.cancel();
    }
    return switch (exit) {
      AgentExit.drained || AgentExit.oneShotDone => XpExit.ok,
      AgentExit.revoked || AgentExit.credentialRejected => XpExit.permission,
      AgentExit.replaced => XpExit.conflict,
      AgentExit.stopped || AgentExit.updateRequired => XpExit.failed,
      AgentExit.updated => await _restarter.restart(paths.currentExecutable, [
        'runner',
        'start',
        '--data-dir',
        paths.root,
        if (slots != null) ...['--slots', '$slots'],
      ], logger.info),
    };
  }

  static Stream<ProcessSignal> _systemSignals() =>
      _merge([ProcessSignal.sigint.watch(), ProcessSignal.sigterm.watch()]);

  static Stream<ProcessSignal> _merge(List<Stream<ProcessSignal>> streams) {
    final controller = StreamController<ProcessSignal>();
    final subscriptions = [
      for (final stream in streams) stream.listen(controller.add),
    ];
    controller.onCancel = () async {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    };
    return controller.stream;
  }
}

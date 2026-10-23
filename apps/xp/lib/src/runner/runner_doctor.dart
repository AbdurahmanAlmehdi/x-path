import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:xp/src/commands/runners_commands.dart' show reachingTheEngine;
import 'package:xp/src/config/xp_config.dart';
import 'package:xp/src/context.dart';
import 'package:xp/src/exit_codes.dart';
import 'package:xp/src/output/format.dart';
import 'package:xp/src/runner/runner_identity.dart';
import 'package:xp/src/runner/runner_options.dart';
import 'package:xp/src/runner/runner_paths.dart';
import 'package:xp/src/runner/runner_runtime.dart';
import 'package:xp/src/runner/service/runner_service.dart';
import 'package:xp/src/runner/service/runner_service_commands.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_engine/xp_engine.dart';

/// How a [DoctorCheck] came out.
enum DoctorState {
  /// It holds.
  ok,

  /// It does not: see the detail and the fix.
  missing,

  /// It was not checked: see the detail.
  skipped,
}

/// One thing `xp runner doctor` checked.
class DoctorCheck {
  /// Creates the check.
  const new({required this.name, required this.state, this.detail, this.fix});

  /// What was checked, for example `android` or `engine`.
  final String name;

  /// How it came out.
  final DoctorState state;

  /// What was found, one sentence without its full stop.
  final String? detail;

  /// What to do about it, one sentence without its full stop.
  final String? fix;

  /// The JSON form.
  Map<String, dynamic> toJson() => {
    'name': name,
    'state': state.name,
    'detail': ?detail,
    'fix': ?fix,
  };
}

/// What `xp runner doctor` found.
class DoctorReport {
  /// Creates the report.
  const new(this.checks);

  /// The checks, in the order they ran.
  final List<DoctorCheck> checks;

  /// Whether the runner can take at least one kind of job: one capability is
  /// offered.
  bool get ready => checks.any(
    (check) => _capabilities.contains(check.name) && check.state == .ok,
  );

  /// The JSON form.
  Map<String, dynamic> toJson() => {
    'ready': ready,
    'checks': [for (final check in checks) check.toJson()],
  };

  static final Set<String> _capabilities = {
    for (final capability in Capability.values) capability.wire,
  };
}

/// Answers "will this machine get jobs?" without connecting, and with no
/// engine at all.
///
/// It runs the probe of the engine ([RunnerProbe]) with this machine's
/// processes and reads it with the same rules, so it says what the engine
/// would find. Then it checks what the runner itself needs: `perl`, its
/// pairing, the engine, its service, SSH to the git hosts and disk space.
class RunnerDoctor {
  /// Creates the doctor for the runner whose data directory is `paths`.
  const new({
    required this._host,
    required this._paths,
    required this._clientFactory,
    required this._serviceStatus,
    this.gitHosts = defaultGitHosts,
  });

  /// The git hosts checked when none is given.
  static const defaultGitHosts = ['github.com'];

  final RunnerHost _host;
  final RunnerPaths _paths;
  final ClientFactory _clientFactory;
  final Future<ServiceStatus> Function() _serviceStatus;

  /// The hosts whose SSH access is checked.
  final List<String> gitHosts;

  /// About how many GB of disk [capability] needs: a Flutter SDK, then
  /// Gradle caches and builds, Xcode's derived data, a Swift build.
  static int _gigabytesFor(Capability capability) => switch (capability) {
    Capability.flutter => 3,
    Capability.android => 5,
    Capability.iosSign => 10,
    Capability.swiftLinux => 2,
  };

  /// Runs every check.
  Future<DoctorReport> examine() async {
    const probe = RunnerProbe();
    final results = await ProbeExecutor(
      runner: _host.runner,
      operatingSystem: _host.operatingSystem,
    ).run(probe.commands);
    final findings = probe.evaluate(results);
    final paired = await _paired();
    return DoctorReport([
      ..._capabilities(findings),
      await _perl(),
      paired.check,
      await _engine(paired.enrollment),
      await _service(),
      for (final host in gitHosts) await _ssh(host),
      await _disk(findings.capabilities),
    ]);
  }

  List<DoctorCheck> _capabilities(ProbeFindings findings) => [
    for (final capability in Capability.values)
      if (findings.capabilities.contains(capability))
        DoctorCheck(name: capability.wire, state: .ok)
      else if (findings.missing.where((m) => m.capability == capability.wire)
          case final missing when missing.isNotEmpty)
        DoctorCheck(
          name: capability.wire,
          state: .missing,
          detail: missing.map((m) => m.reason).join('; '),
          fix: missing.map((m) => m.fix).join('; '),
        ),
  ];

  Future<DoctorCheck> _perl() async {
    String detail;
    try {
      final output = await _host.runner.run('perl', const [
        '-e',
        '1',
      ], timeout: const Duration(seconds: 10));
      if (output.exitCode == 0) {
        return const DoctorCheck(name: 'perl', state: .ok);
      }
      detail = 'perl exited with ${output.exitCode}';
    } on ProcessStartException {
      detail = 'perl not found';
    } on TimeoutException {
      detail = 'perl did not answer in time';
    }
    return DoctorCheck(
      name: 'perl',
      state: .missing,
      detail: detail,
      fix:
          'install perl (apt-get install perl): the runner stops the '
          'processes of a job with it',
    );
  }

  Future<({DoctorCheck check, RunnerEnrollment? enrollment})> _paired() async {
    const pair =
        'pair it with the command `xp runners pair <name>` prints on the '
        'engine';
    DoctorCheck missing(String detail, [String fix = pair]) =>
        DoctorCheck(name: 'paired', state: .missing, detail: detail, fix: fix);
    if (!File(_paths.identityFile).existsSync()) {
      return (
        check: missing('${_paths.root} has no runner.json'),
        enrollment: null,
      );
    }
    try {
      final enrollment = await RunnerEnrollments(
        _paths,
        _host.credentials(_paths),
      ).read();
      if (enrollment == null) {
        return (
          check: missing('runner.json is there, its credential is not'),
          enrollment: null,
        );
      }
      final identity = enrollment.identity;
      return (
        check: DoctorCheck(
          name: 'paired',
          state: .ok,
          detail:
              'as "${identity.name}" (${identity.runnerId}) of '
              '${identity.engine}',
        ),
        enrollment: enrollment,
      );
    } on FormatException catch (error) {
      return (
        check: missing('runner.json cannot be read: ${error.message}'),
        enrollment: null,
      );
    } on SecretStoreException catch (error) {
      return (
        check: missing(
          'the credential cannot be read: ${error.message}',
          'run the doctor as the user the runner runs as, or pair again',
        ),
        enrollment: null,
      );
    }
  }

  Future<DoctorCheck> _engine(RunnerEnrollment? enrollment) async {
    if (enrollment == null) {
      return const DoctorCheck(
        name: 'engine',
        state: .skipped,
        detail: 'not paired, so there is no engine to ask',
      );
    }
    final url = enrollment.identity.engine;
    final client = _clientFactory(Connection(url: url, token: ''));
    try {
      final version = await client.version().timeout(
        const Duration(seconds: 10),
      );
      if (version.apiVersion != apiVersion) {
        return DoctorCheck(
          name: 'engine',
          state: .missing,
          detail:
              'the engine at $url speaks API v${version.apiVersion}, this '
              'runner v$apiVersion',
          fix: 'install the xp of the engine, ${version.version}',
        );
      }
      return DoctorCheck(
        name: 'engine',
        state: .ok,
        detail: '$url runs ${version.version}',
      );
    } on Object catch (error) {
      return DoctorCheck(
        name: 'engine',
        state: .missing,
        detail: 'the engine at $url does not answer: ${_describe(error)}',
        fix:
            'check that the engine runs and that this machine reaches it; '
            'see $reachingTheEngine',
      );
    } finally {
      client.close();
    }
  }

  Future<DoctorCheck> _service() async {
    try {
      final status = await _serviceStatus();
      if (status.running) {
        return DoctorCheck(
          name: 'service',
          state: .ok,
          detail: 'running${status.pid == null ? '' : ' (pid ${status.pid})'}',
        );
      }
      if (!status.installed) {
        return const DoctorCheck(
          name: 'service',
          state: .skipped,
          detail: 'not installed',
          fix: 'to keep the runner running, run: xp runner install-service',
        );
      }
      return DoctorCheck(
        name: 'service',
        state: .missing,
        detail:
            'installed, not running${status.detail == null ? '' : ': '
                      '${status.detail}'}',
        fix: 'see its log; run: xp runner service-status',
      );
    } on Object catch (error) {
      return DoctorCheck(
        name: 'service',
        state: .skipped,
        detail: 'cannot ask the service manager: ${_describe(error)}',
      );
    }
  }

  Future<DoctorCheck> _ssh(String host) async {
    final name = 'ssh $host';
    final ProcessOutput output;
    try {
      // `-T` asks for no shell. The host answers a known key with a greeting
      // and an exit code of its own (GitHub 1, Bitbucket 0); ssh itself
      // fails with 255.
      output = await _host.runner.run('ssh', [
        '-T',
        '-o',
        'BatchMode=yes',
        '-o',
        'ConnectTimeout=10',
        'git@$host',
      ], timeout: const Duration(seconds: 20));
    } on ProcessStartException {
      return DoctorCheck(
        name: name,
        state: .missing,
        detail: 'ssh not found',
        fix: 'install the OpenSSH client (apt-get install openssh-client)',
      );
    } on TimeoutException {
      return DoctorCheck(
        name: name,
        state: .missing,
        detail: '$host did not answer in time',
        fix: 'check that this machine reaches $host on port 22',
      );
    }
    final said = _firstLine('${output.stderr}\n${output.stdout}');
    if (output.exitCode != 255) {
      return DoctorCheck(name: name, state: .ok, detail: said);
    }
    final key = _publicKey();
    final String fix;
    if (said != null && said.contains('Host key verification failed')) {
      fix = 'accept the key of $host once: ssh -T git@$host';
    } else if (key == null) {
      fix =
          'make a key: ssh-keygen -t ed25519, then add '
          '~/.ssh/id_ed25519.pub as a deploy key of the repository';
    } else {
      fix = 'add $key as a deploy key of the repository on $host';
    }
    return DoctorCheck(
      name: name,
      state: .missing,
      detail: said ?? 'ssh exited with 255',
      fix: fix,
    );
  }

  /// The public key ssh offers first, or `null` when there is none.
  String? _publicKey() {
    for (final kind in const ['id_ed25519', 'id_ecdsa', 'id_rsa']) {
      final path = p.join(_host.home, '.ssh', '$kind.pub');
      if (File(path).existsSync()) return path;
    }
    return null;
  }

  Future<DoctorCheck> _disk(Set<Capability> offered) async {
    // The data directory may not exist before the runner is paired.
    var directory = Directory(_paths.root);
    while (!directory.existsSync() && directory.parent.path != directory.path) {
      directory = directory.parent;
    }
    final needs = offered.fold(
      0,
      (sum, capability) => sum + _gigabytesFor(capability),
    );
    int? free;
    try {
      final output = await _host.runner.run('df', [
        '-Pk',
        directory.path,
      ], timeout: const Duration(seconds: 10));
      // `Filesystem 1024-blocks Used Available Capacity Mounted on`.
      final fields = output.stdout
          .trim()
          .split('\n')
          .last
          .split(RegExp(r'\s+'));
      free = output.exitCode == 0 && fields.length >= 4
          ? int.tryParse(fields[3])
          : null;
    } on Object {
      free = null;
    }
    if (free == null) {
      return const DoctorCheck(
        name: 'disk',
        state: .skipped,
        detail: 'df did not say how much space is free',
      );
    }
    final gigabytes = free ~/ (1024 * 1024);
    final detail = '$gigabytes GB free in ${directory.path}';
    if (gigabytes >= needs) {
      return DoctorCheck(name: 'disk', state: .ok, detail: detail);
    }
    return DoctorCheck(
      name: 'disk',
      state: .missing,
      detail: '$detail; what this runner offers needs about $needs GB',
      fix: 'free some space, or give the runner another --data-dir',
    );
  }

  static String? _firstLine(String text) {
    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }

  static String _describe(Object error) => switch (error) {
    final XpClientException e => e.message,
    TimeoutException() => 'no answer within 10 seconds',
    _ => '$error',
  };
}

/// `xp runner doctor [--data-dir <dir>] [--git-host <host>]...`.
class RunnerDoctorCommand extends Command<int> {
  /// Creates the command.
  new(this._context, this._host) {
    argParser
      ..addMultiOption(
        'git-host',
        help: 'A git host whose SSH access to check.',
        valueHelp: 'host',
        defaultsTo: RunnerDoctor.defaultGitHosts,
      )
      ..addFlag(
        'system',
        negatable: false,
        help: 'Linux: check the system unit instead of the user unit.',
      );
    addRunnerDataDirOption(argParser);
  }

  final XpContext _context;
  final RunnerHost _host;

  @override
  String get name => 'doctor';

  @override
  String get description =>
      'Check whether this machine will get jobs, without connecting.';

  @override
  String get invocation =>
      'xp runner doctor [--data-dir <dir>] [--git-host <host>]...';

  @override
  void printUsage() => _context.logger.info(usage);

  @override
  Future<int> run() async {
    final results = argResults!;
    if (results.rest.isNotEmpty) {
      usageException('Unexpected "${results.rest.first}".');
    }
    final paths = runnerPathsOf(results, _host);
    final scope = results.flag('system')
        ? ServiceScope.system
        : ServiceScope.user;
    final report = await RunnerDoctor(
      host: _host,
      paths: paths,
      clientFactory: _context.clientFactory,
      serviceStatus: () => runnerServiceManager(
        _host,
        scope,
      ).status(RunnerServiceDefinition.definition(paths: paths, path: '')),
      gitHosts: results.multiOption('git-host'),
    ).examine();
    final logger = _context.logger;
    if (globalResults?['json'] == true) {
      logger.info(prettyJson(report.toJson()));
    } else {
      for (final check in report.checks) {
        final detail = check.detail == null ? '' : ': ${check.detail}';
        logger.info('${check.state.name.padRight(8)} ${check.name}$detail');
        if (check.fix case final fix?) {
          logger.info('         ${fix[0].toUpperCase()}${fix.substring(1)}.');
        }
      }
      logger.info(
        report.ready
            ? 'This runner can take jobs.'
            : 'This runner offers nothing, so it will get no jobs.',
      );
    }
    return report.ready ? XpExit.ok : XpExit.failed;
  }
}

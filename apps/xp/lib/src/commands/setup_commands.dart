import 'package:args/command_runner.dart';
import 'package:xp/src/commands/xp_command.dart';
import 'package:xp/src/config/xp_config.dart';
import 'package:xp/src/context.dart';
import 'package:xp/src/exit_codes.dart';
import 'package:xp/src/output/format.dart';
import 'package:xp/src/resolve.dart';
import 'package:xp/src/runner/runner_doctor.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';

/// `xp status`: the engine `xp` is connected to, its version and health,
/// the token `xp` holds, whether the engine can reach its secrets, and the
/// project of the current folder. It needs no project.
class StatusCommand extends XpCommand {
  /// Creates the command.
  new(super.context);

  @override
  String get name => 'status';

  @override
  String get description =>
      'Show the engine xp is connected to, its token and its secrets.';

  @override
  String get invocation => 'xp status';

  @override
  Future<int> execute(XpClient client) async {
    positionals(const []);
    final url = (await context.config.engineUrl())!;
    final version = await client.version();
    await client.health();
    final status = await client.status();
    final project = await projectOfRemote(
      client,
      await context.currentRemote(),
    );
    final token = status.token;
    final api = 'API v${version.apiVersion}';
    emit(
      {
        'engine': '$url',
        'version': version.version,
        'apiVersion': version.apiVersion,
        'health': 'ok',
        'token': token.toJson(),
        'secretsLocked': status.secretsLocked,
        'project': ?project?.fullName,
      },
      () => [
        'engine   $url runs xpd ${version.version} ($api)',
        'health   ok',
        'token    "${token.name}" (${token.kind.name})',
        'secrets  ${status.secretsLocked ? _locked : 'unlocked'}',
        if (project != null) 'project  ${project.fullName} (this folder)',
      ].join('\n'),
    );
    return XpExit.ok;
  }
}

const _locked =
    'locked: jobs that need them wait. Unlock them in the XPath app on the '
    'engine machine.';

/// `xp doctor`: whether `xp` can reach its engine, then what the engine
/// finds about the machine it runs on (`GET /doctor`): its own capabilities,
/// secrets, GitHub token, credentials and SSH to other git hosts. The engine
/// checks itself, because this shell may be on another machine with another
/// `PATH`; `xp` adds only its own checks: config, token, reachability.
class DoctorCommand extends Command<int> {
  /// Creates the command.
  new(this._context);

  final XpContext _context;

  @override
  String get name => 'doctor';

  @override
  String get description =>
      'Check that xp reaches its engine, and what the engine finds about '
      'its machine.';

  @override
  String get invocation => 'xp doctor';

  @override
  void printUsage() => _context.logger.info(usage);

  @override
  Future<int> run() =>
      guarded(_context.logger, json: globalResults?['json'] == true, () async {
        if (argResults!.rest.isNotEmpty) {
          usageException('Unexpected "${argResults!.rest.first}".');
        }
        final checks = await _checks();
        final healthy = checks.every((check) => check.state != .missing);
        if (globalResults?['json'] == true) {
          _context.logger.info(
            prettyJson({
              'healthy': healthy,
              'checks': [for (final check in checks) check.toJson()],
            }),
          );
        } else {
          printDoctorChecks(_context.logger, checks);
          _context.logger.info(
            healthy
                ? 'Nothing is missing.'
                : 'Something is missing: see the fixes above.',
          );
        }
        return healthy ? XpExit.ok : XpExit.failed;
      });

  Future<List<DoctorCheck>> _checks() async {
    const connect =
        'connect with the command Settings ▸ CLI and agents '
        'shows in the app, or run: xp connect <url> --token <token>';
    final Connection connection;
    try {
      connection = await _context.config.connection(DeviceTokenKind.cli);
    } on NotConnectedException catch (error) {
      return [
        DoctorCheck(
          name: 'config',
          state: .missing,
          detail: error.message,
          fix: connect,
        ),
      ];
    }
    final client = _context.clientFactory(connection);
    try {
      final config = DoctorCheck(
        name: 'config',
        state: .ok,
        detail: 'the engine is at ${connection.url}',
      );
      try {
        await client.health();
      } on XpClientException catch (error) {
        return [
          config,
          DoctorCheck(
            name: 'engine',
            state: .missing,
            detail: 'the engine does not answer: ${error.message}',
            fix: 'check that the engine runs and that this machine reaches it',
          ),
        ];
      }
      final StatusResponse status;
      try {
        status = await client.status();
      } on ApiException catch (error) {
        if (!error.isUnauthorized) rethrow;
        return [
          config,
          const DoctorCheck(name: 'engine', state: .ok),
          const DoctorCheck(
            name: 'token',
            state: .missing,
            detail: 'the engine refuses the token of xp',
            fix: connect,
          ),
        ];
      }
      final engine = await client.doctor();
      return [
        config,
        const DoctorCheck(name: 'engine', state: .ok),
        DoctorCheck(
          name: 'token',
          state: .ok,
          detail: '"${status.token.name}" (${status.token.kind.name})',
        ),
        for (final check in engine.checks)
          DoctorCheck(
            name: check.name,
            state: DoctorState.values.byName(check.state.wire),
            detail: check.detail,
            fix: check.fix,
          ),
      ];
    } finally {
      client.close();
    }
  }
}

/// `xp disconnect`: forgets the engine and the tokens `xp connect` saved.
/// The tokens keep working on the engine; the environment variables still
/// apply.
class DisconnectCommand extends Command<int> {
  /// Creates the command.
  new(this._context);

  final XpContext _context;

  @override
  String get name => 'disconnect';

  @override
  String get description => 'Forget the engine and the tokens xp saved.';

  @override
  String get invocation => 'xp disconnect';

  @override
  void printUsage() => _context.logger.info(usage);

  @override
  Future<int> run() =>
      guarded(_context.logger, json: globalResults?['json'] == true, () async {
        if (argResults!.rest.isNotEmpty) {
          usageException('Unexpected "${argResults!.rest.first}".');
        }
        final url = await _context.config.forget();
        _context.logger.success(
          url == null
              ? 'Forgot the saved tokens; no engine was saved.'
              : 'Forgot $url and the saved tokens.',
        );
        return XpExit.ok;
      });
}

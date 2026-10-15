import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xpd/src/cli/secrets_command.dart';
import 'package:xpd/src/cli/serve_command.dart';
import 'package:xpd/src/cli/token_command.dart';
import 'package:xpd/src/cli/xpd_context.dart';
import 'package:xpd/src/service/service_commands.dart';
import 'package:xpd/src/version.dart';

/// Exit code for a command line that `xpd` does not understand
/// (`EX_USAGE` in `sysexits.h`).
const _usageExitCode = 64;

/// Runs `xpd` with [args] and returns the process exit code.
///
/// Results go to [out], diagnostics to [err]. `xpd serve` runs until
/// [shutdown] emits. [ghFallbackPaths] is where `xpd secrets import-gh` looks
/// for `gh` when it is not on `PATH`. [processes] starts the programs of the
/// service commands (`launchctl`, `systemctl`); [executable] is the running
/// `xpd` (`Platform.resolvedExecutable`).
Future<int> runXpd(
  List<String> args, {
  required StringSink out,
  required StringSink err,
  required Stream<void> shutdown,
  required Map<String, String> environment,
  required String operatingSystem,
  List<String> ghFallbackPaths = XpdContext.defaultGhFallbackPaths,
  ProcessRunner processes = const IoProcessRunner(),
  String executable = '',
}) async {
  final context = XpdContext(
    out: out,
    err: err,
    shutdown: shutdown,
    environment: environment,
    operatingSystem: operatingSystem,
    ghFallbackPaths: ghFallbackPaths,
    processes: processes,
    executable: executable,
  );
  final runner = _XpdCommandRunner(context)
    ..addCommand(InstallServiceCommand(context))
    ..addCommand(SecretsCommand(context))
    ..addCommand(ServeCommand(context))
    ..addCommand(ServiceStatusCommand(context))
    ..addCommand(TokenCommand(context))
    ..addCommand(UninstallServiceCommand(context));
  try {
    return await runner.run(args) ?? 0;
  } on UsageException catch (e) {
    err.writeln(e);
    return _usageExitCode;
  } on IOException catch (e) {
    err.writeln('xpd: $e');
    return 1;
  }
}

class _XpdCommandRunner extends CommandRunner<int> {
  new(this._context) : super('xpd', 'The XPath engine daemon.') {
    argParser.addFlag(
      'version',
      negatable: false,
      help: 'Print the version and exit.',
    );
  }

  final XpdContext _context;

  @override
  void printUsage() => _context.out.writeln(usage);

  @override
  Future<int?> runCommand(ArgResults topLevelResults) async {
    if (topLevelResults.flag('version')) {
      _context.out.writeln('xpd $packageVersion (API v$apiVersion)');
      return 0;
    }
    if (topLevelResults.arguments.isEmpty) {
      _context.err.writeln(usage);
      return _usageExitCode;
    }
    return await super.runCommand(topLevelResults);
  }
}

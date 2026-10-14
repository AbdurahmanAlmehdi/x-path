import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:cli_completion/cli_completion.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:xp/src/commands/approvals_commands.dart';
import 'package:xp/src/commands/artifacts_commands.dart';
import 'package:xp/src/commands/connect_command.dart';
import 'package:xp/src/commands/projects_commands.dart';
import 'package:xp/src/commands/releases_commands.dart';
import 'package:xp/src/commands/runners_commands.dart';
import 'package:xp/src/commands/runs_commands.dart';
import 'package:xp/src/commands/storage_commands.dart';
import 'package:xp/src/commands/workflows_commands.dart';
import 'package:xp/src/context.dart';
import 'package:xp/src/mcp/mcp_command.dart';
import 'package:xp/src/runner/runner_command.dart';
import 'package:xp/src/version.dart';

const executableName = 'xp';
const description = 'The XPath command-line client.';

/// {@template xp_command_runner}
/// A [CommandRunner] for the CLI.
///
/// ```bash
/// $ xp --version
/// ```
/// {@endtemplate}
class XpCommandRunner extends CompletionCommandRunner<int> {
  /// {@macro xp_command_runner}
  ///
  /// [context] is what the commands run against; by default the real
  /// process's.
  new({Logger? logger, XpContext? context})
    : _logger = context?.logger ?? logger ?? Logger(),
      super(executableName, description) {
    _context = context ?? XpContext.system(logger: _logger);
    // Add root options and flags
    argParser
      ..addFlag(
        'version',
        abbr: 'v',
        negatable: false,
        help: 'Print the current version.',
      )
      ..addFlag(
        'verbose',
        help: 'Noisy logging, including all shell commands executed.',
      )
      ..addFlag(
        'json',
        negatable: false,
        help: 'Print results as JSON, for scripts.',
      );
    addCommand(ConnectCommand(_context));
    addCommand(projectsCommand(_context));
    addCommand(workflowsCommand(_context));
    addCommand(DispatchCommand(_context));
    addCommand(runsCommand(_context));
    addCommand(jobsCommand(_context));
    addCommand(LogsCommand(_context));
    addCommand(approvalsCommand(_context));
    addCommand(gatesCommand(_context));
    addCommand(releasesCommand(_context));
    addCommand(runnersCommand(_context));
    addCommand(runnerCommand(_context));
    addCommand(storageCommand(_context));
    addCommand(artifactsCommand(_context));
    addCommand(McpCommand(_context));
  }

  late final XpContext _context;

  @override
  void printUsage() => _logger.info(usage);

  @override
  String get usageFooter => _exitCodes;

  final Logger _logger;

  @override
  Future<int> run(Iterable<String> args) async {
    try {
      final topLevelResults = parse(args);
      if (topLevelResults['verbose'] == true) {
        _logger.level = Level.verbose;
      }
      return await runCommand(topLevelResults) ?? ExitCode.success.code;
    } on FormatException catch (e, stackTrace) {
      // On format errors, show the commands error message, root usage and
      // exit with an error code
      _logger
        ..err(e.message)
        ..err('$stackTrace')
        ..info('')
        ..info(usage);
      return ExitCode.usage.code;
    } on UsageException catch (e) {
      // On usage errors, show the commands usage message and
      // exit with an error code
      _logger
        ..err(e.message)
        ..info('')
        ..info(e.usage);
      return ExitCode.usage.code;
    }
  }

  @override
  Future<int?> runCommand(ArgResults topLevelResults) async {
    // Fast track completion command
    if (topLevelResults.command?.name == 'completion') {
      await super.runCommand(topLevelResults);
      return ExitCode.success.code;
    }

    // Verbose logs
    _logger
      ..detail('Argument information:')
      ..detail('  Top level options:');
    for (final option in topLevelResults.options) {
      if (topLevelResults.wasParsed(option)) {
        _logger.detail('  - $option: ${topLevelResults[option]}');
      }
    }
    if (topLevelResults.command != null) {
      final commandResult = topLevelResults.command!;
      _logger
        ..detail('  Command: ${commandResult.name}')
        ..detail('    Command options:');
      for (final option in commandResult.options) {
        if (commandResult.wasParsed(option)) {
          _logger.detail(
            '    - $option: ${_shown(option, commandResult[option])}',
          );
        }
      }
    }

    // Run the command or show version
    if (topLevelResults['version'] == true) {
      _logger.info(packageVersion);
      return ExitCode.success.code;
    }
    // The update check runs beside the command and is never waited for
    // longer than a moment: it must not slow a command down.
    final update = _wantsUpdateCheck(topLevelResults)
        ? _context.updateCheck.newerVersion()
        : null;
    final code = await super.runCommand(topLevelResults);
    final newer = await update?.timeout(_updateGrace, onTimeout: () => null);
    if (newer != null) {
      _logger.warn(
        'A newer xp is available: $newer (this is $packageVersion). '
        'See https://github.com/AbdurahmanAlmehdi/x-path/releases',
      );
    }
    return code;
  }

  /// What `--verbose` prints for an option: a token is never printed.
  Object? _shown(String option, Object? value) =>
      _secretOptions.contains(option) ? '***' : value;

  bool _wantsUpdateCheck(ArgResults results) {
    final command = results.command?.name;
    // `xp mcp` talks MCP on standard output and is started by agents; JSON
    // output is read by scripts. Neither wants a notice.
    return command != null && command != 'mcp' && results['json'] != true;
  }
}

const _updateGrace = Duration(milliseconds: 150);

/// The options whose values are tokens.
const _secretOptions = {'token', 'mcp-token'};

const _exitCodes = '''
Exit codes:
  0   success
  1   the command ran, and the job or free-up it watched failed
  64  usage error
  65  the engine refused the content (an invalid workflow)
  66  no such project, job, run, approval, release or artifact
  69  the engine cannot be reached or cannot serve (secrets locked)
  70  the engine failed
  73  conflict (an approval already decided, a project already added)
  77  the token is rejected, or its kind may not do this
  78  not connected: run `xp connect <url> --token <token>`

Settings: ~/.config/xpath/xp.json (the engine URL); the tokens are in the OS
secret store. XP_ENGINE_URL, XP_TOKEN, XP_MCP_TOKEN and XP_CONFIG_DIR override
them. XP_NO_UPDATE_CHECK=1 turns off the daily look for a newer release.''';

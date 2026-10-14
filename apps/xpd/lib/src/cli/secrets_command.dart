import 'package:args/command_runner.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xp_secrets/xp_secrets.dart';
import 'package:xpd/src/cli/gh_executable.dart';
import 'package:xpd/src/cli/xpd_command.dart';
import 'package:xpd/src/cli/xpd_context.dart';
import 'package:xpd/src/test_endpoints.dart';

/// `xpd secrets`: manage the secrets of the engine.
class SecretsCommand extends Command<int> {
  /// Creates the command.
  new(this._context) {
    addSubcommand(SecretsImportGhCommand(_context));
  }

  final XpdContext _context;

  @override
  void printUsage() => _context.out.writeln(usage);

  @override
  String get name => 'secrets';

  @override
  String get description => 'Manage the secrets of the engine.';
}

/// `xpd secrets import-gh`: copies the token of the GitHub CLI into the
/// secret store `xpd serve` uses.
class SecretsImportGhCommand extends XpdCommand {
  /// Creates the command.
  new(super.context) {
    argParser.addOption(
      'gh',
      help:
          'The GitHub CLI to run.\n'
          '(defaults to gh on PATH, then /opt/homebrew/bin/gh, then '
          '/usr/local/bin/gh)',
      valueHelp: 'path',
    );
  }

  @override
  String get name => 'import-gh';

  @override
  String get description =>
      'Store the token of the GitHub CLI (gh auth token) as the GitHub '
      'token of the engine. The token is never printed.';

  @override
  Future<int> run() async {
    final gh =
        argResults!.option('gh') ??
        findGhExecutable(
          path: context.environment['PATH'],
          fallbacks: context.ghFallbackPaths,
        );
    if (gh == null) {
      context.err.writeln(
        'xpd: the GitHub CLI (gh) was not found on PATH or in '
        '${context.ghFallbackPaths.join(', ')}. Install it (brew install gh) '
        'or pass its path with --gh.',
      );
      return 1;
    }
    const runner = IoProcessRunner();
    final secrets = createSecretStore(
      runner: runner,
      dataDir: dataDirectory,
      operatingSystem: TestEndpoints.fromEnvironment(context.environment)
          .secretStoreSystem(context.operatingSystem),
      environment: context.environment,
    );
    try {
      await GitHubTokenImporter(
        runner: runner,
        secrets: secrets,
        ghExecutable: gh,
      ).import();
    } on GitHubTokenImportException catch (error) {
      context.err.writeln(
        'xpd: ${error.message}\n'
        'Check that gh works and is logged in: gh auth status '
        '(log in with: gh auth login).',
      );
      return 1;
    } on SecretsLockedException catch (error) {
      context.err.writeln(
        'xpd: the secrets are locked, so the token was not stored: '
        '${error.message}',
      );
      return 1;
    } on SecretStoreException catch (error) {
      context.err.writeln(
        'xpd: the token could not be stored: ${error.message}',
      );
      return 1;
    }
    context.out.writeln('Imported the GitHub token.');
    return 0;
  }
}

import 'package:args/command_runner.dart';
import 'package:xp/src/commands/xp_command.dart';
import 'package:xp/src/config/xp_config.dart';
import 'package:xp/src/context.dart';
import 'package:xp/src/exit_codes.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';

/// `xp connect <url> --token <token> [--mcp-token <token>]`: saves the engine
/// and the tokens to use with it.
///
/// Before it saves anything it checks that the URL is an XPath engine
/// (`GET /health` and `GET /version`, which need no token) and that each token
/// works (an authenticated `GET /projects`). The app makes the tokens
/// (Settings ▸ CLI and agents, with this command ready to paste), and so
/// does `xpd token create --kind cli` (`--kind mcp` for `xp mcp`) on the
/// engine machine; each is shown once.
class ConnectCommand extends Command<int> {
  /// Creates the command.
  new(this._context) {
    argParser
      ..addOption(
        'token',
        abbr: 't',
        help:
            'The token of this CLI (the app: Settings ▸ CLI and agents; or '
            '`xpd token create --kind cli`).',
        valueHelp: 'token',
      )
      ..addOption(
        'mcp-token',
        help:
            'The token of `xp mcp` (the app: Settings ▸ CLI and agents; or '
            '`xpd token create --kind mcp`).',
        valueHelp: 'token',
      );
  }

  final XpContext _context;

  @override
  String get name => 'connect';

  @override
  String get description => 'Connect to an engine and save the tokens.';

  @override
  String get invocation => 'xp connect [<url>] --token <token>';

  @override
  void printUsage() => _context.logger.info(usage);

  @override
  Future<int> run() => guarded(
    _context.logger,
    json: globalResults?['json'] == true,
    () async {
      final logger = _context.logger;
      final rest = argResults!.rest;
      if (rest.length > 1) usageException('Unexpected "${rest[1]}".');
      final token = argResults!.option('token');
      final mcpToken = argResults!.option('mcp-token');
      if (token == null && mcpToken == null) {
        usageException('Give --token, --mcp-token or both.');
      }
      final Uri url;
      try {
        final given = rest.isEmpty ? null : parseEngineUrl(rest.single);
        final known = given ?? await _context.config.engineUrl();
        if (known == null) usageException('Missing <url>.');
        url = known;
      } on FormatException catch (error) {
        usageException(error.message);
      }

      final tokens = {
        DeviceTokenKind.cli: ?token,
        DeviceTokenKind.mcp: ?mcpToken,
      };
      final probe = _context.clientFactory(Connection(url: url, token: ''));
      try {
        final version = await probe.version();
        await probe.health();
        if (version.apiVersion != apiVersion) {
          logger.err(
            'The engine at $url speaks API v${version.apiVersion}; this xp '
            'speaks v$apiVersion. Install the xp that matches the engine.',
          );
          return XpExit.unavailable;
        }
        for (final entry in tokens.entries) {
          final client = _context.clientFactory(
            Connection(url: url, token: entry.value),
          );
          try {
            await client.listProjects();
          } on ApiException catch (error) {
            if (error.isUnauthorized) {
              logger.err(
                'The engine rejected the ${entry.key.name} token. Make one in '
                'the app (Settings ▸ CLI and agents), or with: xpd token '
                'create --name <name> --kind ${entry.key.name}',
              );
              return XpExit.permission;
            }
            rethrow;
          } finally {
            client.close();
          }
        }
        await _context.config.saveEngineUrl(url);
        for (final entry in tokens.entries) {
          await _context.config.saveToken(entry.key, entry.value);
        }
        final saved = tokens.keys.map((kind) => kind.name).join(' and ');
        logger.success(
          'Connected to $url (xpd ${version.version}, '
          'API v${version.apiVersion}); saved the $saved token.',
        );
        return XpExit.ok;
      } finally {
        probe.close();
      }
    },
  );
}

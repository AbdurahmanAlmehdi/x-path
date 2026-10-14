import 'package:args/command_runner.dart';
import 'package:xp/src/config/xp_config.dart';
import 'package:xp/src/context.dart';
import 'package:xp/src/exit_codes.dart';
import 'package:xp/src/mcp/dart_mcp_adapter.dart';
import 'package:xp/src/mcp/xp_tools.dart';
import 'package:xp/src/version.dart';
import 'package:xp_api/xp_api.dart';

/// `xp mcp`: an MCP server on standard input and output, for agents.
///
/// It uses its own `mcp` token (D-12), the one saved with
/// `xp connect --mcp-token`, never the token of the CLI. Standard output
/// carries only MCP messages; anything else goes to standard error.
class McpCommand extends Command<int> {
  /// Creates the command.
  new(this._context);

  final XpContext _context;

  @override
  String get name => 'mcp';

  @override
  String get description =>
      'Serve XPath to an agent over MCP (stdio). Uses the MCP token.';

  @override
  void printUsage() => _context.logger.info(usage);

  @override
  Future<int> run() async {
    final Connection connection;
    try {
      connection = await _context.config.connection(DeviceTokenKind.mcp);
    } on NotConnectedException catch (error) {
      _context.logger.err(error.message);
      return XpExit.config;
    }
    final client = _context.clientFactory(connection);
    try {
      await serveMcp(
        tools: buildXpTools(client),
        input: _context.stdin,
        output: _context.stdout,
        name: 'xpath',
        version: packageVersion,
        instructions: mcpInstructions,
      );
      return XpExit.ok;
    } finally {
      client.close();
    }
  }
}

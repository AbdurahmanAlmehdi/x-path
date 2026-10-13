import 'package:args/command_runner.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xpd/src/cli/xpd_command.dart';
import 'package:xpd/src/cli/xpd_context.dart';

/// `xpd token`: manage device tokens.
class TokenCommand extends Command<int> {
  /// Creates the command.
  new(this._context) {
    addSubcommand(TokenCreateCommand(_context));
  }

  final XpdContext _context;

  @override
  void printUsage() => _context.out.writeln(usage);

  @override
  String get name => 'token';

  @override
  String get description => 'Manage device tokens.';
}

/// `xpd token create`: issues a token and prints it once.
class TokenCreateCommand extends XpdCommand {
  /// Creates the command.
  new(super.context) {
    argParser
      ..addOption(
        'name',
        abbr: 'n',
        help: 'What you call the device or client, for example "Mac mini".',
      )
      ..addOption(
        'kind',
        abbr: 'k',
        help: 'What will use the token.',
        allowed: DeviceTokenKind.values.map((kind) => kind.name),
      );
  }

  @override
  String get name => 'create';

  @override
  String get description =>
      'Create a device token and print it. It cannot be shown again.';

  @override
  Future<int> run() async {
    final name = argResults!.option('name');
    final kind = argResults!.option('kind');
    if (name == null || name.trim().isEmpty) {
      usageException('--name is required and must not be blank.');
    }
    if (kind == null) usageException('--kind is required.');
    final issued = await withDatabase(
      (database) => TokenService(
        tokens: SqliteDeviceTokenRepository(database),
        clock: const SystemClock(),
      ).issue(name: name, kind: DeviceTokenKind.values.byName(kind)),
    );
    context.err.writeln(
      'Created ${issued.token.kind.name} token "${issued.token.name}" '
      '(${issued.token.id}). This is the only time it is shown:',
    );
    context.out.writeln(issued.secret);
    return 0;
  }
}

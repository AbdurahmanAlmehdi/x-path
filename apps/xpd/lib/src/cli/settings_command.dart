import 'package:args/command_runner.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xpd/src/cli/xpd_command.dart';
import 'package:xpd/src/cli/xpd_context.dart';

/// `xpd settings`: the engine's settings, on the engine machine, without a
/// token. What `xp settings` is through the API.
class SettingsCommand extends Command<int> {
  /// Creates the command.
  new(this._context) {
    addSubcommand(SettingsPublicUrlCommand(_context));
  }

  final XpdContext _context;

  @override
  void printUsage() => _context.out.writeln(usage);

  @override
  String get name => 'settings';

  @override
  String get description => 'Show or change the settings of the engine.';
}

/// `xpd settings public-url [<url> | --clear]`: shows, sets or clears the
/// public URL (ADR 0018, D3), so the first admin of a headless engine can
/// sign in through the proxy without a token. A running engine uses the new
/// URL at once.
class SettingsPublicUrlCommand extends XpdCommand {
  /// Creates the command.
  new(super.context) {
    argParser.addFlag(
      'clear',
      negatable: false,
      help: 'Forget the public URL.',
    );
  }

  @override
  String get name => 'public-url';

  @override
  String get description =>
      'Show or set the HTTPS address browsers reach the engine at through a '
      'proxy, and print it. Browsers sign in to the dashboard on this '
      'machine, or through it.';

  @override
  String get invocation => 'xpd settings public-url [<url> | --clear]';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    final clear = argResults!.flag('clear');
    if (rest.length > 1) usageException('Unexpected "${rest[1]}".');
    if (clear && rest.isNotEmpty) {
      usageException('Give a URL or --clear, not both.');
    }
    try {
      final url = await withDatabase((database) async {
        final service = PublicUrlService(
          settings: SqliteEngineSettingRepository(database),
        );
        if (!clear && rest.isEmpty) return await service.read();
        // The engine machine's user owns the data directory: no token.
        return await service.set(clear ? null : rest.single, by: null);
      });
      final set = url.url;
      if (set == null) {
        context.err.writeln(
          'No public URL is set: browsers sign in to the dashboard on this '
          'machine only. Set one: xpd settings public-url <https url>',
        );
        return 0;
      }
      context.err.writeln(
        'Browsers reach the engine at $set. xpd person create and xpd '
        'person code print a sign-in link there.',
      );
      context.out.writeln(set);
      return 0;
    } on PublicUrlInvalidException catch (error) {
      context.err.writeln('xpd: ${error.message}');
      return 1;
    }
  }
}

import 'package:args/command_runner.dart';
import 'package:xp/src/commands/xp_command.dart';
import 'package:xp/src/context.dart';
import 'package:xp/src/exit_codes.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';

/// `xp settings`: the settings of the engine.
Command<int> settingsCommand(XpContext context) => XpGroup(
  context,
  'settings',
  'Show or change the settings of the engine.',
  [SettingsPublicUrlCommand(context)],
);

/// `xp settings public-url [<url> | --clear]`.
class SettingsPublicUrlCommand extends XpCommand {
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
      'proxy. Browsers sign in to the dashboard on the engine machine, or '
      'through it.';

  @override
  String get invocation => 'xp settings public-url [<url> | --clear]';

  @override
  Future<int> execute(XpClient client) async {
    final rest = argResults!.rest;
    final clear = argResults!.flag('clear');
    if (rest.length > 1) usageException('Unexpected "${rest[1]}".');
    if (clear && rest.isNotEmpty) {
      usageException('Give a URL or --clear, not both.');
    }
    final PublicUrl url;
    if (clear) {
      url = await client.setPublicUrl(null);
    } else if (rest.isEmpty) {
      url = await client.publicUrl();
    } else {
      url = await client.setPublicUrl(rest.single);
    }
    emit(url.toJson(), () {
      final set = url.url;
      if (set == null) {
        return 'No public URL is set: browsers sign in to the dashboard on '
            'the engine machine only. Set one: xp settings public-url <url>';
      }
      return 'Browsers reach the engine at $set.';
    });
    return XpExit.ok;
  }
}

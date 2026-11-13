import 'package:xp/src/commands/xp_command.dart';
import 'package:xp/src/exit_codes.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';

/// `xp dashboard`: opens the engine's web dashboard in the browser, signed
/// in as the person this CLI's token belongs to (D9), with a new one-time
/// sign-in code in the page's fragment.
class DashboardCommand extends XpCommand {
  /// Creates the command.
  new(super.context) {
    argParser.addFlag(
      'print',
      negatable: false,
      help: 'Print the sign-in link instead of opening the browser.',
    );
  }

  @override
  String get name => 'dashboard';

  @override
  String get description =>
      'Open the web dashboard in the browser, signed in. The link works '
      'once, for 10 minutes.';

  @override
  Future<int> execute(XpClient client) async {
    if (argResults!.rest.isNotEmpty) {
      usageException('Unexpected "${argResults!.rest.first}".');
    }
    final url = await client.dashboardSignInUrl();
    if (url.scheme == 'http' && !isLoopbackHost(url.host)) {
      logger.warn(
        'The engine is reached over plain HTTP from another machine, where a '
        'browser cannot sign in. Put an HTTPS proxy in front of it and set '
        'its address: xp settings public-url <https url>',
      );
    }
    final opened = !argResults!.flag('print') && await context.openBrowser(url);
    emit({'url': '$url', 'opened': opened}, () {
      if (opened) {
        return 'Opened the dashboard in the browser. Its sign-in link works '
            'once, for 10 minutes.';
      }
      return 'Open this link to sign in to the dashboard. It works once, for '
          '10 minutes:\n$url';
    });
    return XpExit.ok;
  }
}

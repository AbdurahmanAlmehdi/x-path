import 'package:xp/src/commands/xp_command.dart';
import 'package:xp/src/context.dart';
import 'package:xp/src/exit_codes.dart';
import 'package:xp/src/output/format.dart';
import 'package:xp/src/resolve.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';

/// `xp runners`: the machines that run jobs for the engine (D-08).
///
/// Pairing a runner and revoking it need an `app` or `cli` token; the CLI's
/// token is a `cli` one.
XpGroup runnersCommand(XpContext context) => XpGroup(
  context,
  'runners',
  'List, pair or revoke the runners of the engine.',
  [
    RunnersListCommand(context),
    RunnersPairCommand(context),
    RunnersRevokeCommand(context),
    RunnersUrlCommand(context),
  ],
);

/// Where the guide says how runners reach the engine.
const reachingTheEngine = 'docs/guide/runners.md#reaching-the-engine';

/// `xp runners list [--all]`.
class RunnersListCommand extends XpCommand {
  /// Creates the command.
  new(super.context) {
    argParser.addFlag(
      'all',
      negatable: false,
      help: 'Also list the revoked runners.',
    );
  }

  @override
  String get name => 'list';

  @override
  String get description =>
      'List the runners: where they are, what they offer and what they run.';

  @override
  String get invocation => 'xp runners list [--all]';

  @override
  Future<int> execute(XpClient client) async {
    positionals([]);
    final all = argResults!.flag('all');
    final runners = [
      for (final runner in await client.listRunners())
        if (all || runner.status != RunnerStatus.revoked) runner,
    ];
    emit([for (final runner in runners) runner.toJson()], () {
      if (runners.isEmpty) {
        return 'No runners. Pair one: xp runners pair <name>';
      }
      final table = renderTable(
        [
          'NAME',
          'ID',
          'STATUS',
          'LAST SEEN',
          'CAPABILITIES',
          'SLOTS',
          'JOBS',
          'MACHINE',
        ],
        [
          for (final runner in runners)
            [
              runner.name,
              runner.id,
              runner.activity.name,
              formatTime(runner.lastHeartbeat),
              _listed(runner.capabilities),
              '${runner.jobIds.length}/${runner.slots}',
              _listed(runner.jobIds),
              [
                ?runner.os,
                ?runner.arch,
                if (runner.version case final version?) 'xp $version',
              ].join(' '),
            ],
        ],
      );
      final missing = [
        for (final runner in runners)
          for (final item in runner.missing ?? const <MissingCapability>[])
            '${runner.name}: no ${item.capability}: ${item.explanation}',
      ];
      return [table, if (missing.isNotEmpty) '', ...missing].join('\n');
    });
    return XpExit.ok;
  }
}

String _listed(List<String> items) => items.isEmpty ? '-' : items.join(',');

/// `xp runners pair <name>`.
class RunnersPairCommand extends XpCommand {
  /// Creates the command.
  new(super.context);

  @override
  String get name => 'pair';

  @override
  String get description =>
      'Make a pairing token for a new runner. It works once, for 15 minutes.';

  @override
  String get invocation => 'xp runners pair <name>';

  @override
  Future<int> execute(XpClient client) async {
    final [name] = positionals(['name']);
    final token = await client.createPairingToken(name);
    final engine =
        token.engineUrl ??
        client.baseUrl.toString().replaceFirst(RegExp(r'/+$'), '');
    final local = token.engineUrl == null && _isLoopback(client.baseUrl.host);
    final heading =
        'Pairing token for the runner "${token.name}". On the runner '
        'machine, within 15 minutes:';
    final expiry =
        'It works once and is shown only now. It expires at '
        '${formatTime(token.expiresAt)} UTC (15 minutes).';
    const loopback =
        'This address only works on this machine. Set the address runners '
        'use: xp runners url <url>';
    emit(
      token.toJson(),
      () => [
        heading,
        '  xp runner pair --engine $engine --token ${token.token}',
        '',
        expiry,
        if (local) ...[
          '',
          loopback,
          'How runners reach the engine: $reachingTheEngine',
        ],
      ].join('\n'),
    );
    return XpExit.ok;
  }

  static bool _isLoopback(String host) =>
      host == 'localhost' ||
      host == '::1' ||
      host == '[::1]' ||
      host.startsWith('127.');
}

/// `xp runners revoke <runner>`.
class RunnersRevokeCommand extends XpCommand {
  /// Creates the command.
  new(super.context);

  @override
  String get name => 'revoke';

  @override
  String get description =>
      'Revoke a runner: its credential stops working and its jobs are '
      'handled by the loss rule.';

  @override
  String get invocation => 'xp runners revoke <runner>';

  @override
  Future<int> execute(XpClient client) async {
    final [reference] = positionals(['runner']);
    final runner = await client.revokeRunner(
      await resolveRunner(client, reference),
    );
    emit(
      runner.toJson(),
      () =>
          'Revoked the runner "${runner.name}" (${runner.id}). Jobs it held '
          'are queued again, or wait for a resume when they had a step with '
          'side effects.',
    );
    return XpExit.ok;
  }
}

/// `xp runners url [<url> | --clear]`.
class RunnersUrlCommand extends XpCommand {
  /// Creates the command.
  new(super.context) {
    argParser.addFlag(
      'clear',
      negatable: false,
      help: 'Forget the runner URL.',
    );
  }

  @override
  String get name => 'url';

  @override
  String get description =>
      'Show or set the address runners reach the engine at. Pairing commands '
      'carry it.';

  @override
  String get invocation => 'xp runners url [<url> | --clear]';

  @override
  Future<int> execute(XpClient client) async {
    final rest = argResults!.rest;
    final clear = argResults!.flag('clear');
    if (rest.length > 1) usageException('Unexpected "${rest[1]}".');
    if (clear && rest.isNotEmpty) {
      usageException('Give a URL or --clear, not both.');
    }
    final RunnerUrl url;
    if (clear) {
      url = await client.setRunnerUrl(null);
    } else if (rest.isEmpty) {
      url = await client.runnerUrl();
    } else {
      url = await client.setRunnerUrl(rest.single);
    }
    emit(url.toJson(), () {
      final set = url.url;
      if (set == null) {
        return 'No runner URL is set: pairing commands use the address this '
            'CLI reaches the engine at. Set one: xp runners url <url>\n'
            'How runners reach the engine: $reachingTheEngine';
      }
      const moved =
          'Runners paired already keep their address; pair them again to '
          'move them.';
      return [
        'Runners reach the engine at $set.',
        if (rest.isNotEmpty) moved,
      ].join('\n');
    });
    if (url.warning case final warning?) logger.warn(warning);
    return XpExit.ok;
  }
}

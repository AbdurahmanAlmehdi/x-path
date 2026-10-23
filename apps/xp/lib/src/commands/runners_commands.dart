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
  ],
);

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
    final expiry =
        'It works once and is shown only now. It expires at '
        '${formatTime(token.expiresAt)} UTC (15 minutes).';
    emit(
      token.toJson(),
      () => [
        'Pairing token for the runner "${token.name}":',
        '',
        token.token,
        '',
        expiry,
      ].join('\n'),
    );
    return XpExit.ok;
  }
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

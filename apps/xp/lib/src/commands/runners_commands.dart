import 'package:xp/src/commands/xp_command.dart';
import 'package:xp/src/context.dart';
import 'package:xp/src/exit_codes.dart';
import 'package:xp/src/output/format.dart';
import 'package:xp/src/resolve.dart';
import 'package:xp_client/xp_client.dart';

/// `xp runners`: the machines that run jobs for the engine (D-08).
///
/// Pairing a runner and revoking it need an `app` or `cli` token; the CLI's
/// token is a `cli` one.
XpGroup runnersCommand(XpContext context) => XpGroup(
  context,
  'runners',
  'Pair a runner with the engine, or revoke one.',
  [RunnersPairCommand(context), RunnersRevokeCommand(context)],
);

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

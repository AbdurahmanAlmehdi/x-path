import 'package:xp/src/commands/xp_command.dart';
import 'package:xp/src/context.dart';
import 'package:xp/src/exit_codes.dart';
import 'package:xp/src/output/format.dart';
import 'package:xp/src/resolve.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';

/// `xp approvals`: the owner's decisions on gated actions (D-13).
///
/// The CLI token is a `cli` token, which may approve and deny, unlike the
/// `mcp` token of `xp mcp`.
XpGroup approvalsCommand(XpContext context) => XpGroup(
  context,
  'approvals',
  'List, show, approve and deny the approvals gated actions wait for.',
  [
    ApprovalsListCommand(context),
    ApprovalsShowCommand(context),
    ApprovalsApproveCommand(context),
    ApprovalsDenyCommand(context),
  ],
);

/// The lines `xp approvals show` prints.
String describeApproval(Approval approval) {
  final decided = approval.decidedBy;
  final version = approval.version;
  final subject =
      'project: ${approval.projectId}  sha: ${approval.sha}'
      '${version == null ? '' : '  version: $version'}';
  final times =
      'asked: ${formatTime(approval.createdAt)}  '
      'expires: ${formatTime(approval.expiresAt)}';
  final decision = decided == null
      ? null
      : 'decided by ${decided.name} (${decided.kind.name}) '
            'at ${formatTime(approval.decidedAt)}';
  return [
    '${approval.id}  ${approval.state.wire}  ${approval.action}',
    subject,
    times,
    ?decision,
    if (approval.reason != null) 'reason: ${approval.reason}',
  ].join('\n');
}

/// `xp approvals list`.
class ApprovalsListCommand extends XpCommand {
  /// Creates the command.
  new(super.context) {
    argParser
      ..addOption('project', help: 'Only the approvals of this project.')
      ..addOption(
        'state',
        help: 'Only the approvals in this state.',
        allowed: ApprovalState.values.map((state) => state.wire),
      );
  }

  @override
  String get name => 'list';

  @override
  String get description => 'List the approvals, newest first.';

  @override
  Future<int> execute(XpClient client) async {
    final projectReference = argResults!.option('project');
    final state = argResults!.option('state');
    final approvals = await client.listApprovals(
      projectId: projectReference == null
          ? null
          : await resolveProject(client, projectReference),
      state: state == null
          ? null
          : ApprovalState.values.firstWhere((value) => value.wire == state),
    );
    emit([for (final approval in approvals) approval.toJson()], () {
      if (approvals.isEmpty) return 'No approvals.';
      return renderTable(
        ['ID', 'STATE', 'ACTION', 'PROJECT', 'VERSION', 'ASKED'],
        [
          for (final approval in approvals)
            [
              approval.id,
              approval.state.wire,
              approval.action,
              approval.projectId,
              approval.version ?? '-',
              formatTime(approval.createdAt),
            ],
        ],
      );
    });
    return XpExit.ok;
  }
}

/// `xp approvals show <approval>`.
class ApprovalsShowCommand extends XpCommand {
  /// Creates the command.
  new(super.context);

  @override
  String get name => 'show';

  @override
  String get description => 'Show an approval.';

  @override
  String get invocation => 'xp approvals show <approval>';

  @override
  Future<int> execute(XpClient client) async {
    final [id] = positionals(['approval']);
    final approval = await client.getApproval(id);
    emit(approval.toJson(), () => describeApproval(approval));
    return XpExit.ok;
  }
}

/// `xp approvals approve <approval>` and `deny`: the two differ in the call
/// they make and the words they use.
abstract class _DecideCommand extends XpCommand {
  new(super.context) {
    argParser.addOption('reason', help: 'Why, for the record.');
  }

  Future<Approval> decide(XpClient client, String id, String? reason);

  @override
  Future<int> execute(XpClient client) async {
    final [id] = positionals(['approval']);
    try {
      final approval = await decide(client, id, argResults!.option('reason'));
      emit(approval.toJson(), () => describeApproval(approval));
      return XpExit.ok;
    } on ApiException catch (error) {
      final settled = error.approval;
      if (settled == null) rethrow;
      // Somebody decided first (D-13: the first decision wins).
      logger.err(error.message);
      emit(settled.toJson(), () => describeApproval(settled));
      return XpExit.conflict;
    }
  }
}

/// `xp approvals approve <approval>`.
class ApprovalsApproveCommand extends _DecideCommand {
  /// Creates the command.
  new(super.context);

  @override
  String get name => 'approve';

  @override
  String get description => 'Approve a gated action.';

  @override
  String get invocation => 'xp approvals approve <approval> [--reason <text>]';

  @override
  Future<Approval> decide(XpClient client, String id, String? reason) =>
      client.approve(id, reason: reason);
}

/// `xp approvals deny <approval>`.
class ApprovalsDenyCommand extends _DecideCommand {
  /// Creates the command.
  new(super.context);

  @override
  String get name => 'deny';

  @override
  String get description => 'Deny a gated action.';

  @override
  String get invocation => 'xp approvals deny <approval> [--reason <text>]';

  @override
  Future<Approval> decide(XpClient client, String id, String? reason) =>
      client.deny(id, reason: reason);
}

/// `xp gates`: which actions of a project wait for an approval.
XpGroup gatesCommand(XpContext context) => XpGroup(
  context,
  'gates',
  'Show the gates of a project, or tighten them.',
  [GatesShowCommand(context), GatesTightenCommand(context)],
);

/// `xp gates show <project>`.
class GatesShowCommand extends XpCommand {
  /// Creates the command.
  new(super.context);

  @override
  String get name => 'show';

  @override
  String get description =>
      'Show which actions of a project wait for approval.';

  @override
  String get invocation => 'xp gates show <project>';

  @override
  Future<int> execute(XpClient client) async {
    final [reference] = positionals(['project']);
    final gates = await client.getGates(
      await resolveProject(client, reference),
    );
    emit(gates.toJson(), () => _describeGates(gates));
    return XpExit.ok;
  }
}

String _describeGates(ProjectGates gates) => renderTable(
  ['ACTION', 'GATED'],
  [
    for (final entry in gates.gates.entries)
      [entry.key, if (entry.value) 'yes' else 'no'],
  ],
);

/// `xp gates tighten <project> <action>...`.
class GatesTightenCommand extends XpCommand {
  /// Creates the command.
  new(super.context);

  @override
  String get name => 'tighten';

  @override
  String get description =>
      'Make actions wait for approval. Only the app loosens a gate.';

  @override
  String get invocation => 'xp gates tighten <project> <action>...';

  @override
  Future<int> execute(XpClient client) async {
    final rest = argResults!.rest;
    if (rest.length < 2) {
      usageException('Give a project and at least one action.');
    }
    final projectId = await resolveProject(client, rest.first);
    final current = await client.getGates(projectId);
    final tightened = ProjectGates({
      ...current.gates,
      for (final action in rest.skip(1)) action: true,
    });
    final saved = await client.setGates(projectId, tightened);
    emit(saved.toJson(), () => _describeGates(saved));
    return XpExit.ok;
  }
}

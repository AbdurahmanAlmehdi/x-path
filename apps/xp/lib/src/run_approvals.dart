import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';

/// The approvals a run waits for: the pending ones of its project that its
/// own jobs asked for (D-13). Empty unless the run is waiting for approval.
Future<List<Approval>> pendingApprovalsOf(XpClient client, Run run) async {
  if (run.state != RunState.waitingForApproval) return const [];
  final pending = await client.listApprovals(
    projectId: run.projectId,
    state: ApprovalState.pending,
  );
  return [
    for (final approval in pending)
      if (approval.runId == run.id) approval,
  ];
}

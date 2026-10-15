import 'package:xp_api/xp_api.dart';

import 'job_fixtures.dart';

/// The device that decides on another Mac.
const otherMac = DecidedBy(
  tokenId: 'tok_2',
  name: 'Mac mini',
  kind: DeviceTokenKind.app,
);

/// "Submit 5.4.1 (3283) to the stores", asked at 14:00, 23h 51m left at
/// `testNow`.
final pendingApproval = Approval(
  id: 'apr_1',
  projectId: 'prj_1',
  action: 'store_submission',
  sha: sha,
  version: '5.4.1+3283',
  runId: 'run_1',
  jobId: 'job_upload',
  state: ApprovalState.pending,
  createdAt: local(14, 0),
  expiresAt: local(14, 0).add(const Duration(hours: 24)),
);

/// [pendingApproval], decided as [state] by [otherMac].
Approval decided(
  Approval approval, {
  ApprovalState state = ApprovalState.approved,
  String? reason,
}) => Approval(
  id: approval.id,
  projectId: approval.projectId,
  action: approval.action,
  sha: approval.sha,
  version: approval.version,
  runId: approval.runId,
  jobId: approval.jobId,
  state: state,
  createdAt: approval.createdAt,
  expiresAt: approval.expiresAt,
  decidedAt: state == ApprovalState.expired ? approval.expiresAt : local(14, 5),
  decidedBy: state == ApprovalState.expired ? null : otherMac,
  reason: reason,
);

/// A merge waiting in another project, without a version or job.
final mergeApproval = Approval(
  id: 'apr_2',
  projectId: 'prj_2',
  action: 'merge',
  sha: sha,
  state: ApprovalState.pending,
  createdAt: local(13, 30),
  expiresAt: local(14, 30),
);

/// The upload job that waits for [pendingApproval], building `rel_2`.
final uploadJob = Job(
  id: 'job_upload',
  projectId: 'prj_1',
  workflowVersionId: 'wfv_1',
  runId: 'run_1',
  releaseId: 'rel_2',
  sha: sha,
  name: 'Upload prod',
  stage: 2,
  state: JobState.waitingForApproval,
  createdAt: local(14, 2),
  steps: [
    step(0, 'gate', StepState.waitingForApproval),
    step(1, 'upload.appStore', StepState.pending),
  ],
);

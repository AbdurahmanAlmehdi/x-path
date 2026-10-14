import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/workflows/gate_action.dart';

/// What the engine stores about an approval request (D-13).
///
/// A request is bound to the project, the action, the commit, the version and
/// the run that asked: a different commit or version, or a new dispatch, is a
/// new request, and what the owner decided about one says nothing about
/// another. There is one record per binding for good; a settled record never
/// changes.
class ApprovalRecord extends Equatable {
  /// Creates a record.
  const new({
    required this.id,
    required this.projectId,
    required this.action,
    required this.sha,
    required this.createdAt,
    required this.expiresAt,
    this.version,
    this.runId,
    this.jobId,
    this.state = ApprovalState.pending,
    this.decidedAt,
    this.decidedBy,
    this.reason,
  });

  /// The engine's id, for example `apr_1a2b3c4d5e6f7a8b`.
  final String id;

  /// The project the action happens in.
  final String projectId;

  /// What is to be approved.
  final GateAction action;

  /// The commit the action happens on, in full.
  final String sha;

  /// The version it releases, `x.y.z+build`, when it releases one.
  final String? version;

  /// The run that asked, when the job belongs to one.
  final String? runId;

  /// The first job that asked.
  final String? jobId;

  /// Where it is.
  final ApprovalState state;

  /// When it was asked for.
  final DateTime createdAt;

  /// When it counts as denied if nobody decided.
  final DateTime expiresAt;

  /// When it was decided or expired.
  final DateTime? decidedAt;

  /// Who decided it. `null` while pending and when it expired.
  final DecidedBy? decidedBy;

  /// Why, if the owner said so or the time ran out.
  final String? reason;

  /// Whether [other] asks for the same thing: the binding of D-13 plus the
  /// run.
  bool hasSameBinding(ApprovalRecord other) =>
      projectId == other.projectId &&
      action == other.action &&
      sha == other.sha &&
      version == other.version &&
      runId == other.runId;

  /// Whether nobody decided and the time is up at [now].
  bool isDueAt(DateTime now) =>
      state == ApprovalState.pending && !expiresAt.isAfter(now);

  /// This record, settled.
  ApprovalRecord settled({
    required ApprovalState state,
    required DateTime at,
    DecidedBy? by,
    String? reason,
  }) => ApprovalRecord(
    id: id,
    projectId: projectId,
    action: action,
    sha: sha,
    version: version,
    runId: runId,
    jobId: jobId,
    state: state,
    createdAt: createdAt,
    expiresAt: expiresAt,
    decidedAt: at,
    decidedBy: by,
    reason: reason,
  );

  /// The API form.
  Approval toApi() => Approval(
    id: id,
    projectId: projectId,
    action: action.wire,
    sha: sha,
    version: version,
    runId: runId,
    jobId: jobId,
    state: state,
    createdAt: createdAt,
    expiresAt: expiresAt,
    decidedAt: decidedAt,
    decidedBy: decidedBy,
    reason: reason,
  );

  @override
  List<Object?> get props => [
    id,
    projectId,
    action,
    sha,
    version,
    runId,
    jobId,
    state,
    createdAt,
    expiresAt,
    decidedAt,
    decidedBy,
    reason,
  ];
}

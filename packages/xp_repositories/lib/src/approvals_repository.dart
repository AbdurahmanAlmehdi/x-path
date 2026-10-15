import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_repositories/src/session/engine_session.dart';
import 'package:xp_repositories/src/snapshot.dart';

/// An approval could not be decided because it is not pending any more:
/// another device decided it first (D-13: the first decision wins), or it
/// expired.
class ApprovalAlreadyDecided implements Exception {
  /// Creates the exception with the engine's [message].
  const new(this.message, {this.approval});

  /// What the engine said.
  final String message;

  /// The approval as it stands, when the engine sent it.
  final Approval? approval;

  @override
  String toString() => 'ApprovalAlreadyDecided: $message';
}

/// The approvals and gates of the engine of an [EngineSession] (D-13).
class ApprovalsRepository {
  /// Creates the repository.
  const new(this._session);

  final EngineSession _session;

  /// The approvals, newest first, of [projectId] and in [state] if given,
  /// kept up to date by the approval events.
  Stream<Snapshot<List<Approval>>> watchApprovals({
    String? projectId,
    ApprovalState? state,
  }) => _session.watch(
    key: ['approvals', ?projectId, ?state?.wire].join('.'),
    fetch: (client) => client.listApprovals(projectId: projectId, state: state),
    encode: (approvals) => [
      for (final approval in approvals) approval.toJson(),
    ],
    decode: (json) => [
      for (final approval in json! as List<dynamic>)
        Approval.fromJson(approval as Map<String, dynamic>),
    ],
    refreshOn: (event) => switch (event) {
      ApprovalRequested(projectId: final project) ||
      ApprovalDecided(projectId: final project) ||
      ApprovalExpired(
        projectId: final project,
      ) => projectId == null || project == projectId,
      _ => false,
    },
  );

  /// One approval, kept up to date by its events: a decision made on
  /// another device shows up here.
  Stream<Snapshot<Approval>> watchApproval(String id) => _session.watch(
    key: 'approval.$id',
    fetch: (client) => client.getApproval(id),
    encode: (approval) => approval.toJson(),
    decode: (json) => Approval.fromJson(json! as Map<String, dynamic>),
    refreshOn: (event) => switch (event) {
      ApprovalDecided(:final approvalId) ||
      ApprovalExpired(:final approvalId) => approvalId == id,
      _ => false,
    },
  );

  /// Approves [id]. Throws an [ApprovalAlreadyDecided] with the approval as
  /// it stands when another device decided first or it expired.
  Future<Approval> approve(String id, {String? reason}) => _decide(
    () => _session.call((client) => client.approve(id, reason: reason)),
  );

  /// Denies [id]. Like [approve].
  Future<Approval> deny(String id, {String? reason}) =>
      _decide(() => _session.call((client) => client.deny(id, reason: reason)));

  Future<Approval> _decide(Future<Approval> Function() decide) async {
    try {
      return await decide();
    } on ApiException catch (error) {
      if (error.code != ApiErrorCode.alreadyDecided) rethrow;
      throw ApprovalAlreadyDecided(error.message, approval: error.approval);
    }
  }

  /// Which actions of [projectId] wait for an approval.
  Future<ProjectGates> getGates(String projectId) =>
      _session.call((client) => client.getGates(projectId));

  /// Changes which actions of [projectId] wait for an approval. Only the app
  /// may loosen a gate.
  Future<ProjectGates> setGates(String projectId, ProjectGates gates) =>
      _session.call((client) => client.setGates(projectId, gates));
}

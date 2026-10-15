import 'package:xp_api/xp_api.dart';
import 'package:xp_repositories/src/session/engine_session.dart';
import 'package:xp_repositories/src/snapshot.dart';

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

  /// Approves [id]. Throws an `ApiException` with `already_decided` and the
  /// approval as it stands when another device decided first.
  Future<Approval> approve(String id, {String? reason}) =>
      _session.call((client) => client.approve(id, reason: reason));

  /// Denies [id]. Like [approve].
  Future<Approval> deny(String id, {String? reason}) =>
      _session.call((client) => client.deny(id, reason: reason));

  /// Which actions of [projectId] wait for an approval.
  Future<ProjectGates> getGates(String projectId) =>
      _session.call((client) => client.getGates(projectId));

  /// Changes which actions of [projectId] wait for an approval. Only the app
  /// may loosen a gate.
  Future<ProjectGates> setGates(String projectId, ProjectGates gates) =>
      _session.call((client) => client.setGates(projectId, gates));
}

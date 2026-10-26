import 'package:equatable/equatable.dart';

/// An action that the owner approves before it happens (D-13).
///
/// A workflow names the gate in front of a step (`gate: prod_release`). The
/// engine stops the job there until an approval for exactly this action,
/// project, commit and version exists; the `ApprovalService` keeps them.
enum GateAction {
  /// Releasing a production flavor to the stores.
  prodRelease('prod_release', 'Production release'),

  /// Publishing an over-the-air patch to production.
  prodPatch('prod_patch', 'Production patch'),

  /// Submitting a build to a store for review.
  storeSubmission('store_submission', 'Store submission'),

  /// Pushing a branch or a tag.
  push('push', 'Push'),

  /// Merging a pull request.
  merge('merge', 'Merge'),

  /// Deleting something.
  delete('delete', 'Delete'),

  /// Changing how a release reaches users in a store: pausing, resuming or
  /// completing Apple's phased release, or Google Play's staged rollout
  /// (U7a).
  rollout('rollout', 'Rollout change');

  new(this.wire, this.label);

  /// The name in workflows, on the wire and in the database.
  final String wire;

  /// What it approves, for people.
  final String label;

  /// The action called [wire], or `null`.
  static GateAction? fromWire(String wire) {
    for (final action in values) {
      if (action.wire == wire) return action;
    }
    return null;
  }
}

/// What a gate asks to have approved. An approval binds to all of it
/// (D-13): a different commit or version needs a new approval.
class GateRequest extends Equatable {
  /// Creates a request.
  const new({
    required this.action,
    required this.projectId,
    required this.sha,
    required this.jobId,
    this.version,
  });

  /// What is to be approved.
  final GateAction action;

  /// The project it happens in.
  final String projectId;

  /// The commit it happens on, in full.
  final String sha;

  /// The version it releases, `x.y.z+build`, when it releases one.
  final String? version;

  /// The job that waits, for the owner to see what waits.
  final String jobId;

  @override
  List<Object?> get props => [action, projectId, sha, version, jobId];
}

/// What the owner decided about a gate.
sealed class GateDecision {
  const new();
}

/// The owner approved. The job goes on.
final class GateApproved extends GateDecision {
  /// Creates the decision.
  const new();
}

/// Nobody decided yet. The job waits.
final class GatePending extends GateDecision {
  /// Creates the decision.
  const new({this.approvalId});

  /// The approval that asks, when the approvals know one.
  final String? approvalId;
}

/// The owner denied, or the approval expired (D-13: expired is denied).
final class GateDenied extends GateDecision {
  /// Creates the decision.
  const new(this.reason);

  /// Why, for the owner.
  final String reason;
}

/// Where gates ask for approval (D-13).
///
/// `ApprovalService` implements it: it creates an approval for the request
/// the first time (or finds the one that exists for the same action, project,
/// commit and version), and answers with its state. The workflow engine only
/// asks; it never decides, and nothing in it can approve.
abstract interface class ApprovalGate {
  /// Asks for the approval of [request], or finds out what became of it.
  ///
  /// Asking again for the same request is the same question, not a second
  /// approval.
  Future<GateDecision> check(GateRequest request);
}

/// An [ApprovalGate] for tests of an engine that has no approvals: nothing is
/// ever approved, so every gate holds its job. A job is never let through by
/// the absence of an answer.
class PendingApprovalGate implements ApprovalGate {
  /// Creates the gate.
  const new();

  @override
  Future<GateDecision> check(GateRequest request) async => const GatePending();
}

/// An [ApprovalGate] that answers as the test says, and remembers the
/// questions.
class FakeApprovalGate implements ApprovalGate {
  /// Creates a gate that answers [decision] until it is set otherwise.
  new([this.decision = const GatePending()]);

  /// The answer to every request.
  GateDecision decision;

  /// Every request asked, oldest first.
  final requests = <GateRequest>[];

  @override
  Future<GateDecision> check(GateRequest request) async {
    requests.add(request);
    return decision;
  }
}

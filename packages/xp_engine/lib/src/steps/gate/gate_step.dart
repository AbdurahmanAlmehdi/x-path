import 'package:equatable/equatable.dart';
import 'package:xp_engine/src/json_fields.dart';
import 'package:xp_engine/src/steps/step.dart';
import 'package:xp_engine/src/steps/step_context.dart';
import 'package:xp_engine/src/workflows/gate_action.dart';

/// What a `gate` step asks the owner to approve.
class GateInput extends Equatable {
  /// Creates the input.
  const new({
    required this.action,
    required this.projectId,
    required this.sha,
    this.version,
  });

  /// Reads the input from its stored form.
  ///
  /// Throws a [FormatException] if a field is missing or of the wrong type,
  /// or `action` is not a gate.
  factory fromJson(Map<String, dynamic> json) {
    final wire = requiredString(json, 'action');
    final action = GateAction.fromWire(wire);
    if (action == null) throw FormatException('"$wire" is not a gate.');
    return GateInput(
      action: action,
      projectId: requiredString(json, 'projectId'),
      sha: requiredString(json, 'sha'),
      version: optionalString(json, 'version'),
    );
  }

  /// What is to be approved.
  final GateAction action;

  /// The project it happens in.
  final String projectId;

  /// The commit it happens on.
  final String sha;

  /// The version it releases, `x.y.z+build`, if it releases one.
  final String? version;

  /// The stored form.
  Map<String, dynamic> toJson() => {
    'action': action.wire,
    'projectId': projectId,
    'sha': sha,
    'version': ?version,
  };

  @override
  List<Object?> get props => [action, projectId, sha, version];
}

/// What a `gate` step found.
class GateResult extends Equatable {
  /// Creates the result.
  const new();

  @override
  List<Object?> get props => const [];
}

/// Stops the job until the owner approves an action (D-13).
///
/// The workflow puts a gate in front of a step with `gate: <action>`. The
/// step asks the [ApprovalGate]; while nobody decided the job waits, holding
/// no slot and no runner (state `waiting_for_approval`), and goes on when it
/// is resumed after the decision. The step is asked again each time, so a
/// denial or an expiry fails it. It approves nothing itself.
class GateStep extends Step<GateInput, GateResult> {
  /// Creates the step.
  const new(this._gate);

  final ApprovalGate _gate;

  @override
  String get kind => 'gate';

  @override
  bool sideEffectOf(GateInput input) => false;

  @override
  GateInput decodeInput(Map<String, dynamic> json) => GateInput.fromJson(json);

  @override
  Map<String, dynamic> encodeInput(GateInput input) => input.toJson();

  @override
  Map<String, dynamic> encodeResult(GateResult result) => const {};

  @override
  Future<StepOutcome<GateResult>> run(
    GateInput input,
    StepContext context,
  ) async {
    final decision = await _gate.check(
      GateRequest(
        action: input.action,
        projectId: input.projectId,
        sha: input.sha,
        version: input.version,
        jobId: context.jobId,
      ),
    );
    final what = [
      input.action.wire,
      ?input.version,
      'on ${input.sha.length > 12 ? input.sha.substring(0, 12) : input.sha}',
    ].join(' ');
    switch (decision) {
      case GateApproved():
        return const StepSucceeded(GateResult());
      case GatePending(:final approvalId):
        return StepWaiting(
          'Waiting for the owner to approve $what'
          '${approvalId == null ? '' : ' (approval $approvalId)'}.',
        );
      case GateDenied(:final reason):
        return StepFailed('The owner did not approve $what: $reason');
    }
  }
}

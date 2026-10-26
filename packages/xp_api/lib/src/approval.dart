// `json_serializable` cannot parse `factory .name` constructors yet.
// ignore_for_file: unnecessary_type_name_in_constructor

import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:xp_api/src/device_token_kind.dart';

part 'approval.g.dart';

/// Where an approval is (D-13).
@JsonEnum(valueField: 'wire')
enum ApprovalState {
  /// Nobody decided yet. The job that asked waits.
  pending('pending'),

  /// The owner approved. The job goes on.
  approved('approved'),

  /// The owner denied. The gate step of the job fails.
  denied('denied'),

  /// Nobody decided within 24 hours. Expired counts as denied (D-13): the
  /// gate step of the job fails.
  expired('expired');

  new(this.wire);

  /// The name on the wire and in the database.
  final String wire;

  /// Whether a decision was made, or the time ran out. A settled approval
  /// never changes again.
  bool get isSettled => this != ApprovalState.pending;
}

/// Who decided an approval: the device token that did.
@JsonSerializable()
class DecidedBy extends Equatable {
  /// Creates the description.
  const new({required this.tokenId, required this.name, required this.kind});

  /// Reads a description from its JSON form.
  factory DecidedBy.fromJson(Map<String, dynamic> json) =>
      _$DecidedByFromJson(json);

  /// The id of the device token, for example `tok_1a2b3c4d5e6f7a8b`.
  final String tokenId;

  /// What the owner called the device or client, for example `Mac mini`.
  final String name;

  /// What the token is used by. Only `app` and `cli` tokens decide.
  final DeviceTokenKind kind;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$DecidedByToJson(this);

  @override
  List<Object?> get props => [tokenId, name, kind];
}

/// A request for the owner's approval of an action (D-13), bound to the
/// project, the action, the commit and the version.
@JsonSerializable(explicitToJson: true, includeIfNull: false)
class Approval extends Equatable {
  /// Creates an approval.
  const new({
    required this.id,
    required this.projectId,
    required this.action,
    required this.sha,
    required this.state,
    required this.createdAt,
    required this.expiresAt,
    this.version,
    this.runId,
    this.jobId,
    this.decidedAt,
    this.decidedBy,
    this.reason,
  });

  /// Reads an approval from its JSON form.
  factory Approval.fromJson(Map<String, dynamic> json) =>
      _$ApprovalFromJson(json);

  /// The engine's id, for example `apr_1a2b3c4d5e6f7a8b`.
  final String id;

  /// The project the action happens in.
  final String projectId;

  /// What is to be approved: `prod_release`, `prod_patch`,
  /// `store_submission`, `push`, `merge`, `delete` or `rollout`.
  final String action;

  /// The commit the action happens on, in full.
  final String sha;

  /// The version it releases, `x.y.z+build`, when it releases one.
  final String? version;

  /// The run that asked.
  final String? runId;

  /// The first job that asked. Other jobs of the run that reach the same
  /// gate share the approval.
  final String? jobId;

  /// Where it is.
  final ApprovalState state;

  /// When it was asked for, in UTC.
  final DateTime createdAt;

  /// When it counts as denied if nobody decided, in UTC: 24 hours after
  /// [createdAt].
  final DateTime expiresAt;

  /// When it was decided or expired, in UTC.
  final DateTime? decidedAt;

  /// Who approved or denied it. Absent while it is pending and when it
  /// expired.
  final DecidedBy? decidedBy;

  /// Why, when the owner said or the time ran out.
  final String? reason;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$ApprovalToJson(this);

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

/// The body of `GET /approvals`.
@JsonSerializable(explicitToJson: true)
class ApprovalsResponse extends Equatable {
  /// Creates a response.
  const new(this.approvals);

  /// Reads a response from its JSON form.
  factory ApprovalsResponse.fromJson(Map<String, dynamic> json) =>
      _$ApprovalsResponseFromJson(json);

  /// The approvals, newest first.
  final List<Approval> approvals;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$ApprovalsResponseToJson(this);

  @override
  List<Object?> get props => [approvals];
}

/// The optional body of `POST /approvals/{id}/approve` and `/deny`.
@JsonSerializable(includeIfNull: false, checked: true)
class DecisionRequest extends Equatable {
  /// Creates a request.
  const new({this.reason});

  /// Reads a request from its JSON form.
  factory DecisionRequest.fromJson(Map<String, dynamic> json) =>
      _$DecisionRequestFromJson(json);

  /// Why, for the record.
  final String? reason;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$DecisionRequestToJson(this);

  @override
  List<Object?> get props => [reason];
}

/// Which actions of a project are gated (D-13): the body of
/// `PUT /projects/{id}/gates` and the answer of `GET`.
///
/// The keys are the actions (see [Approval.action]); `true` means the action
/// waits for an approval. An action that is left out is gated, so a project
/// that never set anything has every gate on.
@JsonSerializable(checked: true)
class ProjectGates extends Equatable {
  /// Creates the gates.
  const new(this.gates);

  /// Reads the gates from their JSON form.
  factory ProjectGates.fromJson(Map<String, dynamic> json) =>
      _$ProjectGatesFromJson(json);

  /// Whether each action is gated.
  final Map<String, bool> gates;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$ProjectGatesToJson(this);

  @override
  List<Object?> get props => [gates];
}

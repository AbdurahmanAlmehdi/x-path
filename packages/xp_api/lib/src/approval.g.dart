// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'approval.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DecidedBy _$DecidedByFromJson(Map<String, dynamic> json) => DecidedBy(
  tokenId: json['tokenId'] as String,
  name: json['name'] as String,
  kind: $enumDecode(_$DeviceTokenKindEnumMap, json['kind']),
);

Map<String, dynamic> _$DecidedByToJson(DecidedBy instance) => <String, dynamic>{
  'tokenId': instance.tokenId,
  'name': instance.name,
  'kind': _$DeviceTokenKindEnumMap[instance.kind]!,
};

const _$DeviceTokenKindEnumMap = {
  DeviceTokenKind.app: 'app',
  DeviceTokenKind.cli: 'cli',
  DeviceTokenKind.mcp: 'mcp',
  DeviceTokenKind.runner: 'runner',
};

Approval _$ApprovalFromJson(Map<String, dynamic> json) => Approval(
  id: json['id'] as String,
  projectId: json['projectId'] as String,
  action: json['action'] as String,
  sha: json['sha'] as String,
  state: $enumDecode(_$ApprovalStateEnumMap, json['state']),
  createdAt: DateTime.parse(json['createdAt'] as String),
  expiresAt: DateTime.parse(json['expiresAt'] as String),
  version: json['version'] as String?,
  runId: json['runId'] as String?,
  jobId: json['jobId'] as String?,
  decidedAt: json['decidedAt'] == null
      ? null
      : DateTime.parse(json['decidedAt'] as String),
  decidedBy: json['decidedBy'] == null
      ? null
      : DecidedBy.fromJson(json['decidedBy'] as Map<String, dynamic>),
  reason: json['reason'] as String?,
);

Map<String, dynamic> _$ApprovalToJson(Approval instance) => <String, dynamic>{
  'id': instance.id,
  'projectId': instance.projectId,
  'action': instance.action,
  'sha': instance.sha,
  'version': ?instance.version,
  'runId': ?instance.runId,
  'jobId': ?instance.jobId,
  'state': _$ApprovalStateEnumMap[instance.state]!,
  'createdAt': instance.createdAt.toIso8601String(),
  'expiresAt': instance.expiresAt.toIso8601String(),
  'decidedAt': ?instance.decidedAt?.toIso8601String(),
  'decidedBy': ?instance.decidedBy?.toJson(),
  'reason': ?instance.reason,
};

const _$ApprovalStateEnumMap = {
  ApprovalState.pending: 'pending',
  ApprovalState.approved: 'approved',
  ApprovalState.denied: 'denied',
  ApprovalState.expired: 'expired',
};

ApprovalsResponse _$ApprovalsResponseFromJson(Map<String, dynamic> json) =>
    ApprovalsResponse(
      (json['approvals'] as List<dynamic>)
          .map((e) => Approval.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$ApprovalsResponseToJson(ApprovalsResponse instance) =>
    <String, dynamic>{
      'approvals': instance.approvals.map((e) => e.toJson()).toList(),
    };

DecisionRequest _$DecisionRequestFromJson(Map<String, dynamic> json) =>
    $checkedCreate('DecisionRequest', json, ($checkedConvert) {
      final val = DecisionRequest(
        reason: $checkedConvert('reason', (v) => v as String?),
      );
      return val;
    });

Map<String, dynamic> _$DecisionRequestToJson(DecisionRequest instance) =>
    <String, dynamic>{'reason': ?instance.reason};

ProjectGates _$ProjectGatesFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ProjectGates', json, ($checkedConvert) {
      final val = ProjectGates(
        $checkedConvert('gates', (v) => Map<String, bool>.from(v as Map)),
      );
      return val;
    });

Map<String, dynamic> _$ProjectGatesToJson(ProjectGates instance) =>
    <String, dynamic>{'gates': instance.gates};

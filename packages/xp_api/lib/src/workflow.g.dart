// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'workflow.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

WorkflowVersionInfo _$WorkflowVersionInfoFromJson(Map<String, dynamic> json) =>
    WorkflowVersionInfo(
      id: json['id'] as String,
      version: (json['version'] as num).toInt(),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );

Map<String, dynamic> _$WorkflowVersionInfoToJson(
  WorkflowVersionInfo instance,
) => <String, dynamic>{
  'id': instance.id,
  'version': instance.version,
  'createdAt': instance.createdAt.toIso8601String(),
};

WorkflowInput _$WorkflowInputFromJson(Map<String, dynamic> json) =>
    WorkflowInput(
      name: json['name'] as String,
      type: $enumDecodeNullable(_$InputTypeEnumMap, json['type']),
      description: json['description'] as String?,
      options: (json['options'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      defaultValue: json['default'],
      required: json['required'] as bool? ?? false,
    );

Map<String, dynamic> _$WorkflowInputToJson(WorkflowInput instance) =>
    <String, dynamic>{
      'name': instance.name,
      'type': ?_$InputTypeEnumMap[instance.type],
      'description': ?instance.description,
      'options': ?instance.options,
      'default': ?instance.defaultValue,
      'required': instance.required,
    };

const _$InputTypeEnumMap = {
  InputType.string: 'string',
  InputType.boolean: 'boolean',
  InputType.choice: 'choice',
  InputType.json: 'json',
  InputType.release: 'release',
};

Workflow _$WorkflowFromJson(Map<String, dynamic> json) => Workflow(
  id: json['id'] as String,
  projectId: json['projectId'] as String,
  name: json['name'] as String,
  builtin: json['builtin'] as bool,
  version: WorkflowVersionInfo.fromJson(
    json['version'] as Map<String, dynamic>,
  ),
  versions: (json['versions'] as List<dynamic>)
      .map((e) => WorkflowVersionInfo.fromJson(e as Map<String, dynamic>))
      .toList(),
  yaml: json['yaml'] as String,
  inputs:
      (json['inputs'] as List<dynamic>?)
          ?.map((e) => WorkflowInput.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
);

Map<String, dynamic> _$WorkflowToJson(Workflow instance) => <String, dynamic>{
  'id': instance.id,
  'projectId': instance.projectId,
  'name': instance.name,
  'builtin': instance.builtin,
  'version': instance.version.toJson(),
  'versions': instance.versions.map((e) => e.toJson()).toList(),
  'yaml': instance.yaml,
  'inputs': instance.inputs.map((e) => e.toJson()).toList(),
};

WorkflowSummary _$WorkflowSummaryFromJson(Map<String, dynamic> json) =>
    WorkflowSummary(
      id: json['id'] as String,
      projectId: json['projectId'] as String,
      name: json['name'] as String,
      builtin: json['builtin'] as bool,
      version: WorkflowVersionInfo.fromJson(
        json['version'] as Map<String, dynamic>,
      ),
    );

Map<String, dynamic> _$WorkflowSummaryToJson(WorkflowSummary instance) =>
    <String, dynamic>{
      'id': instance.id,
      'projectId': instance.projectId,
      'name': instance.name,
      'builtin': instance.builtin,
      'version': instance.version.toJson(),
    };

WorkflowsResponse _$WorkflowsResponseFromJson(Map<String, dynamic> json) =>
    WorkflowsResponse(
      (json['workflows'] as List<dynamic>)
          .map((e) => WorkflowSummary.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$WorkflowsResponseToJson(WorkflowsResponse instance) =>
    <String, dynamic>{
      'workflows': instance.workflows.map((e) => e.toJson()).toList(),
    };

CreateWorkflowRequest _$CreateWorkflowRequestFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('CreateWorkflowRequest', json, ($checkedConvert) {
  final val = CreateWorkflowRequest(
    name: $checkedConvert('name', (v) => v as String),
    yaml: $checkedConvert('yaml', (v) => v as String),
  );
  return val;
});

Map<String, dynamic> _$CreateWorkflowRequestToJson(
  CreateWorkflowRequest instance,
) => <String, dynamic>{'name': instance.name, 'yaml': instance.yaml};

WorkflowYamlRequest _$WorkflowYamlRequestFromJson(Map<String, dynamic> json) =>
    $checkedCreate('WorkflowYamlRequest', json, ($checkedConvert) {
      final val = WorkflowYamlRequest(
        yaml: $checkedConvert('yaml', (v) => v as String),
      );
      return val;
    });

Map<String, dynamic> _$WorkflowYamlRequestToJson(
  WorkflowYamlRequest instance,
) => <String, dynamic>{'yaml': instance.yaml};

WorkflowIssue _$WorkflowIssueFromJson(Map<String, dynamic> json) =>
    WorkflowIssue(
      line: (json['line'] as num).toInt(),
      column: (json['column'] as num).toInt(),
      message: json['message'] as String,
    );

Map<String, dynamic> _$WorkflowIssueToJson(WorkflowIssue instance) =>
    <String, dynamic>{
      'line': instance.line,
      'column': instance.column,
      'message': instance.message,
    };

ValidateWorkflowResponse _$ValidateWorkflowResponseFromJson(
  Map<String, dynamic> json,
) => ValidateWorkflowResponse(
  valid: json['valid'] as bool,
  issues:
      (json['issues'] as List<dynamic>?)
          ?.map((e) => WorkflowIssue.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
);

Map<String, dynamic> _$ValidateWorkflowResponseToJson(
  ValidateWorkflowResponse instance,
) => <String, dynamic>{
  'valid': instance.valid,
  'issues': instance.issues.map((e) => e.toJson()).toList(),
};

StepType _$StepTypeFromJson(Map<String, dynamic> json) => StepType(
  kind: json['kind'] as String,
  withKeys:
      (json['with'] as List<dynamic>?)?.map((e) => e as String).toList() ??
      const [],
);

Map<String, dynamic> _$StepTypeToJson(StepType instance) => <String, dynamic>{
  'kind': instance.kind,
  'with': instance.withKeys,
};

WorkflowSchema _$WorkflowSchemaFromJson(Map<String, dynamic> json) =>
    WorkflowSchema(
      schema: (json['schema'] as num).toInt(),
      steps: (json['steps'] as List<dynamic>)
          .map((e) => StepType.fromJson(e as Map<String, dynamic>))
          .toList(),
      gates: (json['gates'] as List<dynamic>).map((e) => e as String).toList(),
      capabilities: (json['capabilities'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      matrixAxes: (json['matrixAxes'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      platforms: (json['platforms'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
    );

Map<String, dynamic> _$WorkflowSchemaToJson(WorkflowSchema instance) =>
    <String, dynamic>{
      'schema': instance.schema,
      'steps': instance.steps.map((e) => e.toJson()).toList(),
      'gates': instance.gates,
      'capabilities': instance.capabilities,
      'matrixAxes': instance.matrixAxes,
      'platforms': instance.platforms,
    };

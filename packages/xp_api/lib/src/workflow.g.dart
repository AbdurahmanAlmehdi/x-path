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
  basedOn: json['basedOn'] == null
      ? null
      : WorkflowBasedOn.fromJson(json['basedOn'] as Map<String, dynamic>),
  archivedAt: json['archivedAt'] == null
      ? null
      : DateTime.parse(json['archivedAt'] as String),
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
  'basedOn': ?instance.basedOn?.toJson(),
  'archivedAt': ?instance.archivedAt?.toIso8601String(),
};

WorkflowBasedOn _$WorkflowBasedOnFromJson(Map<String, dynamic> json) =>
    WorkflowBasedOn(
      builtin: json['builtin'] as String,
      version: (json['version'] as num).toInt(),
    );

Map<String, dynamic> _$WorkflowBasedOnToJson(WorkflowBasedOn instance) =>
    <String, dynamic>{'builtin': instance.builtin, 'version': instance.version};

WorkflowSummary _$WorkflowSummaryFromJson(Map<String, dynamic> json) =>
    WorkflowSummary(
      id: json['id'] as String,
      projectId: json['projectId'] as String,
      name: json['name'] as String,
      builtin: json['builtin'] as bool,
      version: WorkflowVersionInfo.fromJson(
        json['version'] as Map<String, dynamic>,
      ),
      title: json['title'] as String?,
      description: json['description'] as String?,
      basedOn: json['basedOn'] == null
          ? null
          : WorkflowBasedOn.fromJson(json['basedOn'] as Map<String, dynamic>),
      archivedAt: json['archivedAt'] == null
          ? null
          : DateTime.parse(json['archivedAt'] as String),
    );

Map<String, dynamic> _$WorkflowSummaryToJson(WorkflowSummary instance) =>
    <String, dynamic>{
      'id': instance.id,
      'projectId': instance.projectId,
      'name': instance.name,
      'builtin': instance.builtin,
      'version': instance.version.toJson(),
      'title': ?instance.title,
      'description': ?instance.description,
      'basedOn': ?instance.basedOn?.toJson(),
      'archivedAt': ?instance.archivedAt?.toIso8601String(),
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

WorkflowTemplate _$WorkflowTemplateFromJson(Map<String, dynamic> json) =>
    WorkflowTemplate(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      yaml: json['yaml'] as String,
    );

Map<String, dynamic> _$WorkflowTemplateToJson(WorkflowTemplate instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'description': instance.description,
      'yaml': instance.yaml,
    };

WorkflowTemplatesResponse _$WorkflowTemplatesResponseFromJson(
  Map<String, dynamic> json,
) => WorkflowTemplatesResponse(
  (json['templates'] as List<dynamic>)
      .map((e) => WorkflowTemplate.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$WorkflowTemplatesResponseToJson(
  WorkflowTemplatesResponse instance,
) => <String, dynamic>{
  'templates': instance.templates.map((e) => e.toJson()).toList(),
};

CreateWorkflowRequest _$CreateWorkflowRequestFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('CreateWorkflowRequest', json, ($checkedConvert) {
  final val = CreateWorkflowRequest(
    name: $checkedConvert('name', (v) => v as String),
    yaml: $checkedConvert('yaml', (v) => v as String),
    basedOn: $checkedConvert(
      'basedOn',
      (v) => v == null
          ? null
          : WorkflowBasedOn.fromJson(v as Map<String, dynamic>),
    ),
  );
  return val;
});

Map<String, dynamic> _$CreateWorkflowRequestToJson(
  CreateWorkflowRequest instance,
) => <String, dynamic>{
  'name': instance.name,
  'yaml': instance.yaml,
  'basedOn': ?instance.basedOn,
};

UpdateWorkflowRequest _$UpdateWorkflowRequestFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('UpdateWorkflowRequest', json, ($checkedConvert) {
  final val = UpdateWorkflowRequest(
    name: $checkedConvert('name', (v) => v as String?),
    archived: $checkedConvert('archived', (v) => v as bool?),
    basedOnVersion: $checkedConvert(
      'basedOnVersion',
      (v) => (v as num?)?.toInt(),
    ),
  );
  return val;
});

Map<String, dynamic> _$UpdateWorkflowRequestToJson(
  UpdateWorkflowRequest instance,
) => <String, dynamic>{
  'name': ?instance.name,
  'archived': ?instance.archived,
  'basedOnVersion': ?instance.basedOnVersion,
};

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
      hint: json['hint'] as String?,
    );

Map<String, dynamic> _$WorkflowIssueToJson(WorkflowIssue instance) =>
    <String, dynamic>{
      'line': instance.line,
      'column': instance.column,
      'message': instance.message,
      'hint': ?instance.hint,
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

StepKeySchema _$StepKeySchemaFromJson(Map<String, dynamic> json) =>
    StepKeySchema(
      name: json['name'] as String,
      type:
          $enumDecodeNullable(_$StepKeyTypeEnumMap, json['type']) ??
          StepKeyType.any,
      required: json['required'] as bool? ?? false,
      defaultValue: json['default'],
      options: (json['options'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      description: json['description'] as String? ?? '',
    );

Map<String, dynamic> _$StepKeySchemaToJson(StepKeySchema instance) =>
    <String, dynamic>{
      'name': instance.name,
      'type': _$StepKeyTypeEnumMap[instance.type]!,
      'required': instance.required,
      'default': ?instance.defaultValue,
      'options': ?instance.options,
      'description': instance.description,
    };

const _$StepKeyTypeEnumMap = {
  StepKeyType.string: 'string',
  StepKeyType.boolean: 'boolean',
  StepKeyType.number: 'number',
  StepKeyType.list: 'list',
  StepKeyType.map: 'map',
  StepKeyType.any: 'any',
};

StepType _$StepTypeFromJson(Map<String, dynamic> json) => StepType(
  kind: json['kind'] as String,
  withKeys:
      (json['with'] as List<dynamic>?)?.map((e) => e as String).toList() ??
      const [],
  title: json['title'] as String? ?? '',
  description: json['description'] as String? ?? '',
  group: json['group'] as String? ?? '',
  capabilities:
      (json['capabilities'] as List<dynamic>?)
          ?.map((e) => (e as List<dynamic>).map((e) => e as String).toList())
          .toList() ??
      const [],
  keys:
      (json['keys'] as List<dynamic>?)
          ?.map((e) => StepKeySchema.fromJson(e as Map<String, dynamic>))
          .toList() ??
      const [],
);

Map<String, dynamic> _$StepTypeToJson(StepType instance) => <String, dynamic>{
  'kind': instance.kind,
  'with': instance.withKeys,
  'title': instance.title,
  'description': instance.description,
  'group': instance.group,
  'capabilities': instance.capabilities,
  'keys': instance.keys.map((e) => e.toJson()).toList(),
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
      gateLabels:
          (json['gateLabels'] as Map<String, dynamic>?)?.map(
            (k, e) => MapEntry(k, e as String),
          ) ??
          const {},
      variables:
          (json['variables'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
    );

Map<String, dynamic> _$WorkflowSchemaToJson(WorkflowSchema instance) =>
    <String, dynamic>{
      'schema': instance.schema,
      'steps': instance.steps.map((e) => e.toJson()).toList(),
      'gates': instance.gates,
      'capabilities': instance.capabilities,
      'matrixAxes': instance.matrixAxes,
      'platforms': instance.platforms,
      'gateLabels': instance.gateLabels,
      'variables': instance.variables,
    };

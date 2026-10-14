// `json_serializable` cannot parse `factory .name` constructors yet.
// ignore_for_file: unnecessary_type_name_in_constructor

import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'workflow.g.dart';

/// One version of a workflow. Every save makes a new one; a job keeps the
/// exact version it ran.
@JsonSerializable(includeIfNull: false)
class WorkflowVersionInfo extends Equatable {
  /// Creates the description.
  const new({required this.id, required this.version, required this.createdAt});

  /// Reads a version from its JSON form.
  factory WorkflowVersionInfo.fromJson(Map<String, dynamic> json) =>
      _$WorkflowVersionInfoFromJson(json);

  /// The engine's id, which `Job.workflowVersionId` refers to.
  final String id;

  /// The number of the version, from 1.
  final int version;

  /// When it was saved, in UTC.
  final DateTime createdAt;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$WorkflowVersionInfoToJson(this);

  @override
  List<Object?> get props => [id, version, createdAt];
}

/// A workflow of a project, with the YAML of one of its versions.
@JsonSerializable(explicitToJson: true, includeIfNull: false)
class Workflow extends Equatable {
  /// Creates a workflow.
  const new({
    required this.id,
    required this.projectId,
    required this.name,
    required this.builtin,
    required this.version,
    required this.versions,
    required this.yaml,
  });

  /// Reads a workflow from its JSON form.
  factory Workflow.fromJson(Map<String, dynamic> json) =>
      _$WorkflowFromJson(json);

  /// The engine's id, for example `wf_1a2b3c4d5e6f7a8b`.
  final String id;

  /// The project it belongs to.
  final String projectId;

  /// Its name, unique in the project, for example `dev-build`.
  final String name;

  /// Whether the engine made it. A built-in cannot be edited or deleted;
  /// copy its YAML into a workflow of your own.
  final bool builtin;

  /// The version [yaml] belongs to.
  final WorkflowVersionInfo version;

  /// Every version, oldest first.
  final List<WorkflowVersionInfo> versions;

  /// The YAML document of [version].
  final String yaml;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$WorkflowToJson(this);

  @override
  List<Object?> get props => [
    id,
    projectId,
    name,
    builtin,
    version,
    versions,
    yaml,
  ];
}

/// A workflow without its YAML, for lists.
@JsonSerializable(explicitToJson: true, includeIfNull: false)
class WorkflowSummary extends Equatable {
  /// Creates a summary.
  const new({
    required this.id,
    required this.projectId,
    required this.name,
    required this.builtin,
    required this.version,
  });

  /// Reads a summary from its JSON form.
  factory WorkflowSummary.fromJson(Map<String, dynamic> json) =>
      _$WorkflowSummaryFromJson(json);

  /// The engine's id.
  final String id;

  /// The project it belongs to.
  final String projectId;

  /// Its name.
  final String name;

  /// Whether the engine made it.
  final bool builtin;

  /// The newest version.
  final WorkflowVersionInfo version;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$WorkflowSummaryToJson(this);

  @override
  List<Object?> get props => [id, projectId, name, builtin, version];
}

/// The body of `GET /projects/{id}/workflows`.
@JsonSerializable(explicitToJson: true)
class WorkflowsResponse extends Equatable {
  /// Creates a response.
  const new(this.workflows);

  /// Reads a response from its JSON form.
  factory WorkflowsResponse.fromJson(Map<String, dynamic> json) =>
      _$WorkflowsResponseFromJson(json);

  /// The workflows of the project, by name.
  final List<WorkflowSummary> workflows;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$WorkflowsResponseToJson(this);

  @override
  List<Object?> get props => [workflows];
}

/// The body of `POST /projects/{id}/workflows`.
@JsonSerializable(includeIfNull: false, checked: true)
class CreateWorkflowRequest extends Equatable {
  /// Creates a request.
  const new({required this.name, required this.yaml});

  /// Reads a request from its JSON form.
  factory CreateWorkflowRequest.fromJson(Map<String, dynamic> json) =>
      _$CreateWorkflowRequestFromJson(json);

  /// The name of the new workflow: letters, digits, `.`, `_` and `-`.
  final String name;

  /// The workflow document.
  final String yaml;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$CreateWorkflowRequestToJson(this);

  @override
  List<Object?> get props => [name, yaml];
}

/// The body of `PUT /projects/{id}/workflows/{workflowId}` and of
/// `POST /projects/{id}/workflows/validate`.
@JsonSerializable(includeIfNull: false, checked: true)
class WorkflowYamlRequest extends Equatable {
  /// Creates a request.
  const new({required this.yaml});

  /// Reads a request from its JSON form.
  factory WorkflowYamlRequest.fromJson(Map<String, dynamic> json) =>
      _$WorkflowYamlRequestFromJson(json);

  /// The workflow document.
  final String yaml;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$WorkflowYamlRequestToJson(this);

  @override
  List<Object?> get props => [yaml];
}

/// A problem in a workflow document, at the place it was found.
@JsonSerializable()
class WorkflowIssue extends Equatable {
  /// Creates an issue.
  const new({required this.line, required this.column, required this.message});

  /// Reads an issue from its JSON form.
  factory WorkflowIssue.fromJson(Map<String, dynamic> json) =>
      _$WorkflowIssueFromJson(json);

  /// The line, from 1.
  final int line;

  /// The column, from 1.
  final int column;

  /// What is wrong and, where it helps, what is allowed instead.
  final String message;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$WorkflowIssueToJson(this);

  @override
  String toString() => '$line:$column: $message';

  @override
  List<Object?> get props => [line, column, message];
}

/// The body of `POST /projects/{id}/workflows/validate`.
@JsonSerializable(explicitToJson: true)
class ValidateWorkflowResponse extends Equatable {
  /// Creates a response.
  const new({required this.valid, this.issues = const []});

  /// Reads a response from its JSON form.
  factory ValidateWorkflowResponse.fromJson(Map<String, dynamic> json) =>
      _$ValidateWorkflowResponseFromJson(json);

  /// Whether the document has no issues.
  final bool valid;

  /// The issues, in the order of the document.
  final List<WorkflowIssue> issues;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$ValidateWorkflowResponseToJson(this);

  @override
  List<Object?> get props => [valid, issues];
}

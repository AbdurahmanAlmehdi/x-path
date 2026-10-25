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

/// What kind of value an input of a workflow takes.
@JsonEnum(valueField: 'wire')
enum InputType {
  /// Text, sent as it is typed.
  string('string'),

  /// `true` or `false`.
  boolean('boolean'),

  /// One of the input's `options`.
  choice('choice'),

  /// Any JSON value: a list, a map, a number.
  json('json'),

  /// A release of the project, `x.y.z+build`; the dispatch's
  /// `releaseVersion` when it gives none.
  release('release');

  new(this.wire);

  /// The name in a workflow document and on the wire.
  final String wire;
}

/// An input a workflow declares: what a dispatch can set as `inputs.<name>`.
@JsonSerializable(includeIfNull: false)
class WorkflowInput extends Equatable {
  /// Creates the description.
  const new({
    required this.name,
    this.type,
    this.description,
    this.options,
    this.defaultValue,
    this.required = false,
  });

  /// Reads an input from its JSON form.
  factory WorkflowInput.fromJson(Map<String, dynamic> json) =>
      _$WorkflowInputFromJson(json);

  /// The name under `inputs`.
  final String name;

  /// What it takes; `null` for an input without a type, which takes any
  /// value (a client sends text, or JSON when the text parses as JSON).
  final InputType? type;

  /// What it is for.
  final String? description;

  /// The values a [InputType.choice] input may take.
  final List<String>? options;

  /// The value when a dispatch gives none.
  @JsonKey(name: 'default')
  final Object? defaultValue;

  /// Whether a dispatch without it is refused.
  final bool required;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$WorkflowInputToJson(this);

  @override
  List<Object?> get props => [
    name,
    type,
    description,
    options,
    defaultValue,
    required,
  ];
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
    this.inputs = const [],
    this.basedOn,
    this.archivedAt,
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

  /// The inputs [yaml] declares, as the engine reads them; empty when it
  /// declares none or no longer reads as a workflow.
  final List<WorkflowInput> inputs;

  /// The built-in this workflow was copied from, and its version then.
  final WorkflowBasedOn? basedOn;

  /// When it was archived: it keeps its runs and versions, and is
  /// not offered to dispatch. `null` while it is not archived.
  final DateTime? archivedAt;

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
    inputs,
    basedOn,
    archivedAt,
  ];
}

/// The built-in a workflow was copied from ("Save as"), and the version of
/// it the copy started from. When the built-in has a newer version, the
/// owner can compare.
@JsonSerializable()
class WorkflowBasedOn extends Equatable {
  /// Creates the link.
  const new({required this.builtin, required this.version});

  /// Reads the link from its JSON form.
  factory WorkflowBasedOn.fromJson(Map<String, dynamic> json) =>
      _$WorkflowBasedOnFromJson(json);

  /// The name of the built-in, such as `dev-build`.
  final String builtin;

  /// The version of the built-in the copy started from, or last caught up
  /// with.
  final int version;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$WorkflowBasedOnToJson(this);

  @override
  List<Object?> get props => [builtin, version];
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
    this.title,
    this.description,
    this.basedOn,
    this.archivedAt,
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

  /// What the newest version calls the workflow (its `name`), for example
  /// "Dev build".
  final String? title;

  /// What the newest version says the workflow is for.
  final String? description;

  /// The built-in this workflow was copied from, and its version then.
  final WorkflowBasedOn? basedOn;

  /// When it was archived; `null` while it is not.
  final DateTime? archivedAt;

  /// Whether it is archived: kept, and not offered to dispatch.
  bool get archived => archivedAt != null;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$WorkflowSummaryToJson(this);

  @override
  List<Object?> get props => [
    id,
    projectId,
    name,
    builtin,
    version,
    title,
    description,
    basedOn,
    archivedAt,
  ];
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

/// A document a new workflow can start from (`GET /workflows/templates`).
@JsonSerializable()
class WorkflowTemplate extends Equatable {
  /// Creates a template.
  const new({
    required this.id,
    required this.title,
    required this.description,
    required this.yaml,
  });

  /// Reads a template from its JSON form.
  factory WorkflowTemplate.fromJson(Map<String, dynamic> json) =>
      _$WorkflowTemplateFromJson(json);

  /// Its id, such as `android-firebase`.
  final String id;

  /// Its name for people, such as "Android to Firebase".
  final String title;

  /// What a workflow made from it does.
  final String description;

  /// The document, valid as it is.
  final String yaml;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$WorkflowTemplateToJson(this);

  @override
  List<Object?> get props => [id, title, description, yaml];
}

/// The body of `GET /workflows/templates`.
@JsonSerializable(explicitToJson: true)
class WorkflowTemplatesResponse extends Equatable {
  /// Creates a response.
  const new(this.templates);

  /// Reads a response from its JSON form.
  factory WorkflowTemplatesResponse.fromJson(Map<String, dynamic> json) =>
      _$WorkflowTemplatesResponseFromJson(json);

  /// The templates, in the order to offer them.
  final List<WorkflowTemplate> templates;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$WorkflowTemplatesResponseToJson(this);

  @override
  List<Object?> get props => [templates];
}

/// The body of `POST /projects/{id}/workflows`.
@JsonSerializable(includeIfNull: false, checked: true, explicitToJson: true)
class CreateWorkflowRequest extends Equatable {
  /// Creates a request.
  const new({required this.name, required this.yaml, this.basedOn});

  /// Reads a request from its JSON form.
  factory CreateWorkflowRequest.fromJson(Map<String, dynamic> json) =>
      _$CreateWorkflowRequestFromJson(json);

  /// The name of the new workflow: letters, digits, `.`, `_` and `-`.
  final String name;

  /// The workflow document.
  final String yaml;

  /// The built-in the document is a copy of, when it is one.
  final WorkflowBasedOn? basedOn;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$CreateWorkflowRequestToJson(this);

  @override
  List<Object?> get props => [name, yaml, basedOn];
}

/// The body of `PATCH /projects/{id}/workflows/{workflowId}`: what changes,
/// each field only when it is given.
@JsonSerializable(includeIfNull: false, checked: true)
class UpdateWorkflowRequest extends Equatable {
  /// Creates a request.
  const new({this.name, this.archived, this.basedOnVersion});

  /// Reads a request from its JSON form.
  factory UpdateWorkflowRequest.fromJson(Map<String, dynamic> json) =>
      _$UpdateWorkflowRequestFromJson(json);

  /// A new name.
  final String? name;

  /// Whether the workflow is archived.
  final bool? archived;

  /// The version of its built-in the copy has caught up with, after a
  /// compare.
  final int? basedOnVersion;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$UpdateWorkflowRequestToJson(this);

  @override
  List<Object?> get props => [name, archived, basedOnVersion];
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
@JsonSerializable(includeIfNull: false)
class WorkflowIssue extends Equatable {
  /// Creates an issue.
  const new({
    required this.line,
    required this.column,
    required this.message,
    this.hint,
  });

  /// Reads an issue from its JSON form.
  factory WorkflowIssue.fromJson(Map<String, dynamic> json) =>
      _$WorkflowIssueFromJson(json);

  /// The line, from 1.
  final int line;

  /// The column, from 1.
  final int column;

  /// What is wrong.
  final String message;

  /// What to write instead, for example `Did you mean "inputs.appIds"?`, or
  /// what is allowed there.
  final String? hint;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$WorkflowIssueToJson(this);

  @override
  String toString() => '$line:$column: ${[message, ?hint].join(' ')}';

  @override
  List<Object?> get props => [line, column, message, hint];
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

/// What a key of `with` holds.
enum StepKeyType {
  /// A string, such as a path.
  @JsonValue('string')
  string,

  /// `true` or `false`.
  @JsonValue('boolean')
  boolean,

  /// A number.
  @JsonValue('number')
  number,

  /// A list of strings.
  @JsonValue('list')
  list,

  /// A mapping of strings to strings.
  @JsonValue('map')
  map,

  /// Anything; the step type checks it.
  @JsonValue('any')
  any,
}

/// A key a step type takes under `with`.
@JsonSerializable(includeIfNull: false)
class StepKeySchema extends Equatable {
  /// Creates the key.
  const new({
    required this.name,
    this.type = StepKeyType.any,
    this.required = false,
    this.defaultValue,
    this.options,
    this.description = '',
  });

  /// Reads a key from its JSON form.
  factory StepKeySchema.fromJson(Map<String, dynamic> json) =>
      _$StepKeySchemaFromJson(json);

  /// Its name under `with`.
  final String name;

  /// What it holds.
  final StepKeyType type;

  /// Whether a step of its type must give it.
  final bool required;

  /// What the step uses when it is not given, when that is one value.
  @JsonKey(name: 'default')
  final Object? defaultValue;

  /// The strings it may take, when they are fixed: one of them, or for a
  /// list, some of them.
  final List<String>? options;

  /// What it is for, in a sentence.
  final String description;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$StepKeySchemaToJson(this);

  @override
  List<Object?> get props => [
    name,
    type,
    required,
    defaultValue,
    options,
    description,
  ];
}

/// A step type of the engine: what it does and the keys it takes under
/// `with`.
@JsonSerializable(explicitToJson: true)
class StepType extends Equatable {
  /// Creates a step type.
  const new({
    required this.kind,
    this.withKeys = const [],
    this.title = '',
    this.description = '',
    this.group = '',
    this.capabilities = const [],
    this.keys = const [],
  });

  /// Reads a step type from its JSON form.
  factory StepType.fromJson(Map<String, dynamic> json) =>
      _$StepTypeFromJson(json);

  /// The name a step uses as its `kind`, for example `build.android`.
  final String kind;

  /// The keys a step of this type takes under `with`, sorted.
  @JsonKey(name: 'with')
  final List<String> withKeys;

  /// Its name for people, for example "Build Android".
  final String title;

  /// What it does, in a sentence or two.
  final String description;

  /// Where an editor lists it: Source, Checks, Build, Upload, GitHub or
  /// Other.
  final String group;

  /// What a runner needs to run it: any one of these sets will do. Empty
  /// when the engine runs it.
  final List<List<String>> capabilities;

  /// The keys of [withKeys] with their types, in the order the step type
  /// gives them.
  final List<StepKeySchema> keys;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$StepTypeToJson(this);

  @override
  List<Object?> get props => [
    kind,
    withKeys,
    title,
    description,
    group,
    capabilities,
    keys,
  ];
}

/// The body of `GET /workflows/schema`: what a workflow document of this
/// engine may name, for editors.
@JsonSerializable(explicitToJson: true)
class WorkflowSchema extends Equatable {
  /// Creates the schema.
  const new({
    required this.schema,
    required this.steps,
    required this.gates,
    required this.capabilities,
    required this.matrixAxes,
    required this.platforms,
    this.gateLabels = const {},
    this.variables = const [],
  });

  /// Reads the schema from its JSON form.
  factory WorkflowSchema.fromJson(Map<String, dynamic> json) =>
      _$WorkflowSchemaFromJson(json);

  /// The version of the document the engine reads (`schema: 1`).
  final int schema;

  /// The step types, by kind.
  final List<StepType> steps;

  /// The actions a step can be gated on (`gate:`).
  final List<String> gates;

  /// The capabilities a job can ask for (`capabilities:`).
  final List<String> capabilities;

  /// The axes a job's matrix can have (`platform`, `flavor`).
  final List<String> matrixAxes;

  /// The values of the `platform` axis.
  final List<String> platforms;

  /// What each of [gates] approves, for people: `prod_release` is
  /// "Release to production".
  final Map<String, String> gateLabels;

  /// What an expression can read, as paths: `platform`, `flavor.prod`,
  /// `app.name`. `inputs` holds the inputs a workflow declares, and
  /// `flavor` and `platform` are there in a job whose matrix has them.
  final List<String> variables;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$WorkflowSchemaToJson(this);

  @override
  List<Object?> get props => [
    schema,
    steps,
    gates,
    capabilities,
    matrixAxes,
    platforms,
    gateLabels,
    variables,
  ];
}

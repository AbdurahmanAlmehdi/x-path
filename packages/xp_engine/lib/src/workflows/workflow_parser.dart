import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/scheduler/capability.dart';
import 'package:xp_engine/src/workflows/expression.dart';
import 'package:xp_engine/src/workflows/gate_action.dart';
import 'package:xp_engine/src/workflows/step_catalog.dart';
import 'package:xp_engine/src/workflows/suggestion.dart';
import 'package:xp_engine/src/workflows/workflow_definition.dart';
import 'package:yaml/yaml.dart';

/// What reading a workflow document gave.
class WorkflowParseResult {
  /// Creates a result.
  const new({this.definition, this.issues = const []});

  /// The workflow, when the document has no issue.
  final WorkflowDefinition? definition;

  /// The problems, in the order of the document. Empty when it is valid.
  final List<WorkflowIssue> issues;

  /// Whether the document has no issue.
  bool get isValid => issues.isEmpty;
}

final _name = RegExp(r'^[A-Za-z][A-Za-z0-9_-]*$');
final _inputName = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

/// Reads and checks workflow documents (schema 1).
///
/// A document is YAML:
///
/// ```yaml
/// schema: 1                    # required
/// name: Dev build              # optional
/// description: ...             # optional
/// lock: project                # optional: one run at a time per project
/// inputs:                      # optional: variables a dispatch can set
///   notes: {description: Release notes, default: ''}
/// stages:                      # required, run in order
///   - name: build
///     jobs:                    # run in parallel, as slots allow
///       build:
///         name: Build ${{ platform }}      # optional
///         matrix:                          # optional: one job per cell
///           platform: ${{ platforms }}     # or [android, ios]
///           flavor: ${{ flavors }}
///         if: platform == 'android'        # optional: a cell without a job
///         capabilities: [flutter]          # optional, besides the steps'
///         steps:
///           - kind: build.android          # a step type
///             with: {artifact: apk}        # what the step type takes
///             if: flavor.prod              # optional: left out when false
///             gate: prod_release           # optional: approve first (D-13)
/// ```
///
/// Every problem is reported with the line and column where it is, so an
/// editor can underline it. The parser reports as many as it can find in one
/// pass.
class WorkflowParser {
  /// Creates a parser that knows the step types of [catalog].
  const new(this.catalog);

  /// The step types a document may use.
  final StepCatalog catalog;

  /// Reads [source].
  WorkflowParseResult parse(String source) {
    final reader = _Reader(catalog);
    final definition = reader.read(source);
    return reader.issues.isEmpty
        ? WorkflowParseResult(definition: definition)
        : WorkflowParseResult(issues: reader.issues);
  }
}

class _Reader {
  new(this.catalog);

  final StepCatalog catalog;
  final issues = <WorkflowIssue>[];
  final _jobIds = <String, SourcePosition>{};
  var _inputNames = const <String>{};

  WorkflowDefinition? read(String source) {
    final YamlNode root;
    try {
      root = loadYamlNode(source);
    } on YamlException catch (error) {
      final start = error.span?.start;
      _issue(
        (start?.line ?? 0) + 1,
        (start?.column ?? 0) + 1,
        'The document is not valid YAML: ${error.message}',
      );
      return null;
    }
    if (root is! YamlMap) {
      _issueAt(
        root,
        root is YamlScalar && root.value == null
            ? 'The workflow is empty.'
            : 'A workflow is a mapping with "schema" and "stages".',
      );
      return null;
    }
    _checkKeys(root, 'the workflow', const {
      'schema',
      'name',
      'description',
      'lock',
      'inputs',
      'stages',
    });
    final schema = root.nodes['schema'];
    if (schema == null) {
      _issueAt(root, 'Add "schema: $workflowSchemaVersion".');
    } else if (!(schema is YamlScalar &&
        schema.value == workflowSchemaVersion)) {
      _issueAt(schema, '"schema" must be $workflowSchemaVersion.');
    }
    final name = _optionalText(root, 'name');
    final description = _optionalText(root, 'description');
    final lockNode = root.nodes['lock'];
    var locksProject = false;
    if (lockNode != null) {
      if (lockNode is YamlScalar && lockNode.value == 'project') {
        locksProject = true;
      } else {
        _issueAt(lockNode, '"lock" can only be "project".');
      }
    }
    final inputs = _inputs(root.nodes['inputs']);
    _inputNames = {for (final input in inputs) input.name};
    final stages = _stages(root.nodes['stages'], root);
    _checkCommitSources(stages);
    return WorkflowDefinition(
      name: name,
      description: description,
      locksProject: locksProject,
      inputs: inputs,
      stages: stages,
    );
  }

  // ---------------------------------------------------------------- inputs

  List<InputDefinition> _inputs(YamlNode? node) {
    if (node == null) return const [];
    if (node is! YamlMap) {
      _issueAt(node, '"inputs" is a mapping from a name to its definition.');
      return const [];
    }
    final inputs = <InputDefinition>[];
    for (final entry in node.nodes.entries) {
      final key = entry.key as YamlNode;
      final name = '${(key as YamlScalar).value}';
      if (!_inputName.hasMatch(name)) {
        _issueAt(key, '"$name" is not an input name: letters, digits and _.');
      }
      final value = entry.value;
      if (value is YamlScalar && value.value == null) {
        inputs.add(InputDefinition(name: name, position: _position(key)));
        continue;
      }
      if (value is! YamlMap) {
        _issueAt(value, 'An input is a mapping, or empty.');
        continue;
      }
      _checkKeys(value, 'input "$name"', const {
        'description',
        'type',
        'options',
        'default',
        'required',
      });
      final (type, options) = _inputType(value);
      final requiredNode = value.nodes['required'];
      var isRequired = false;
      if (requiredNode != null) {
        if (requiredNode is YamlScalar && requiredNode.value is bool) {
          isRequired = requiredNode.value as bool;
        } else {
          _issueAt(requiredNode, '"required" must be true or false.');
        }
      }
      if (isRequired && value.nodes.containsKey('default')) {
        _issueAt(value, 'An input with a default cannot be required.');
      }
      final input = InputDefinition(
        name: name,
        position: _position(key),
        type: type,
        options: options,
        description: _optionalText(value, 'description'),
        defaultValue: _plain(value.nodes['default']),
        required: isRequired,
      );
      if (value.nodes['default'] case final node?) {
        if (input.problemOf(input.defaultValue) case final problem?) {
          _issueAt(node, 'The default of "$name" $problem.');
        }
      }
      inputs.add(input);
    }
    return inputs;
  }

  /// The `type` of an input and the `options` of a choice (UX-04).
  (InputType?, List<String>?) _inputType(YamlMap input) {
    final typeNode = input.nodes['type'];
    InputType? type;
    if (typeNode != null) {
      type = InputType.values
          .where((candidate) => '${typeNode.value}' == candidate.wire)
          .firstOrNull;
      if (type == null || typeNode is! YamlScalar) {
        _issueAt(
          typeNode,
          'Unknown input type "${typeNode.value}".',
          hint: suggestion('${typeNode.value}', [
            for (final type in InputType.values) type.wire,
          ]),
        );
        type = null;
      }
    }
    final optionsNode = input.nodes['options'];
    List<String>? options;
    if (optionsNode != null) {
      if (optionsNode is YamlList &&
          optionsNode.nodes.isNotEmpty &&
          optionsNode.nodes.every(
            (option) => option is YamlScalar && option.value is String,
          )) {
        options = [for (final option in optionsNode.nodes) '${option.value}'];
      } else {
        _issueAt(optionsNode, '"options" is a list of strings.');
      }
      if (type != InputType.choice) {
        _issueAt(optionsNode, '"options" go with "type: choice".');
      }
    } else if (type == InputType.choice) {
      _issueAt(input, 'A choice input needs "options".');
    }
    return (type, options);
  }

  // ---------------------------------------------------------------- stages

  List<StageDefinition> _stages(YamlNode? node, YamlMap root) {
    if (node == null) {
      _issueAt(root, 'Add "stages", a list of stages that run in order.');
      return const [];
    }
    if (node is! YamlList || node.isEmpty) {
      _issueAt(node, '"stages" is a list with at least one stage.');
      return const [];
    }
    final stages = <StageDefinition>[];
    for (final item in node.nodes) {
      final stage = _stage(item);
      if (stage != null) stages.add(stage);
    }
    return stages;
  }

  StageDefinition? _stage(YamlNode node) {
    if (node is! YamlMap) {
      _issueAt(node, 'A stage is a mapping with "name" and "jobs".');
      return null;
    }
    _checkKeys(node, 'a stage', const {'name', 'jobs'});
    final name = _requiredText(node, 'name', 'a stage');
    final jobsNode = node.nodes['jobs'];
    final jobs = <JobDefinition>[];
    if (jobsNode == null) {
      _issueAt(node, 'Add "jobs" to the stage.');
    } else if (jobsNode is! YamlMap || jobsNode.isEmpty) {
      _issueAt(jobsNode, '"jobs" is a mapping from a job id to its job.');
    } else {
      for (final entry in jobsNode.nodes.entries) {
        final job = _job(entry.key as YamlScalar, entry.value);
        if (job != null) jobs.add(job);
      }
    }
    return StageDefinition(
      name: name ?? '',
      jobs: jobs,
      position: _position(node),
    );
  }

  JobDefinition? _job(YamlScalar key, YamlNode node) {
    final id = '${key.value}';
    if (!_name.hasMatch(id)) {
      _issueAt(
        key,
        '"$id" is not a job id: start with a letter, then letters, digits, '
        '- and _.',
      );
    }
    final earlier = _jobIds[id];
    if (earlier != null) {
      _issueAt(key, 'The job id "$id" is used at $earlier already.');
    }
    _jobIds[id] = _position(key);
    if (node is! YamlMap) {
      _issueAt(node, 'A job is a mapping with "steps".');
      return null;
    }
    _checkKeys(node, 'job "$id"', const {
      'name',
      'matrix',
      'if',
      'capabilities',
      'steps',
    });
    final matrix = _matrix(node.nodes['matrix'], id);
    final variables = {
      ...dispatchVariables,
      for (final axis in matrix) axis.name,
    };
    final nameNode = node.nodes['name'];
    Template? name;
    if (nameNode != null) {
      final text = _text(nameNode, '"name"');
      if (text != null) name = _template(nameNode, text, variables);
    }
    final (condition, _) = _condition(node, variables);
    final capabilities = _capabilities(node.nodes['capabilities']);
    final steps = _steps(node.nodes['steps'], node, variables, id);
    return JobDefinition(
      id: id,
      name: name,
      matrix: matrix,
      condition: condition,
      capabilities: capabilities,
      steps: steps,
      position: _position(key),
    );
  }

  List<MatrixAxis> _matrix(YamlNode? node, String jobId) {
    if (node == null) return const [];
    if (node is! YamlMap || node.isEmpty) {
      _issueAt(node, '"matrix" is a mapping from "platform" or "flavor".');
      return const [];
    }
    final axes = <MatrixAxis>[];
    for (final entry in node.nodes.entries) {
      final key = entry.key as YamlScalar;
      final name = '${key.value}';
      if (!matrixAxes.contains(name)) {
        _issueAt(
          key,
          'Unknown matrix axis "$name".',
          hint: suggestion(name, matrixAxes),
        );
        continue;
      }
      final value = entry.value;
      if (value is YamlList) {
        final values = <String>[];
        for (final item in value.nodes) {
          final text = item is YamlScalar && item.value is String
              ? item.value as String
              : null;
          if (text == null) {
            _issueAt(item, 'A matrix value is a string.');
          } else if (name == 'platform' && !platformNames.contains(text)) {
            _issueAt(
              item,
              'Unknown platform "$text".',
              hint: suggestion(text, platformNames),
            );
          } else {
            values.add(text);
          }
        }
        axes.add(
          MatrixAxis(name: name, values: values, position: _position(key)),
        );
      } else if (value is YamlScalar && value.value is String) {
        final template = _template(value, value.value as String, {
          ...dispatchVariables,
        });
        if (template != null && template.isSinglePlaceholder) {
          axes.add(
            MatrixAxis(
              name: name,
              reference: template,
              position: _position(key),
            ),
          );
        } else if (template != null) {
          _issueAt(value, r'Use one placeholder, such as ${{ platforms }}.');
        }
      } else {
        _issueAt(
          value,
          'A matrix axis is a list of values or a placeholder such as '
          r'${{ platforms }}.',
        );
      }
    }
    return axes;
  }

  List<Capability> _capabilities(YamlNode? node) {
    if (node == null) return const [];
    if (node is! YamlList) {
      _issueAt(node, '"capabilities" is a list.');
      return const [];
    }
    final capabilities = <Capability>[];
    for (final item in node.nodes) {
      final capability = item is YamlScalar && item.value is String
          ? Capability.fromWire(item.value as String)
          : null;
      if (capability == null) {
        final name = item is YamlScalar ? '${item.value}' : '';
        _issueAt(
          item,
          'Unknown capability "$name".',
          hint: suggestion(name, [
            for (final capability in Capability.values) capability.wire,
          ]),
        );
      } else {
        capabilities.add(capability);
      }
    }
    return capabilities;
  }

  // ----------------------------------------------------------------- steps

  List<StepDefinition> _steps(
    YamlNode? node,
    YamlMap job,
    Set<String> variables,
    String jobId,
  ) {
    if (node == null) {
      _issueAt(job, 'Add "steps" to job "$jobId".');
      return const [];
    }
    if (node is! YamlList || node.isEmpty) {
      _issueAt(node, '"steps" is a list with at least one step.');
      return const [];
    }
    return [for (final item in node.nodes) ?_step(item, variables)];
  }

  StepDefinition? _step(YamlNode node, Set<String> variables) {
    if (node is! YamlMap) {
      _issueAt(node, 'A step is a mapping with a "kind".');
      return null;
    }
    _checkKeys(node, 'a step', const {'kind', 'with', 'if', 'gate'});
    final kindNode = node.nodes['kind'];
    final kind = _requiredText(node, 'kind', 'a step');
    Map<String, StepKey>? keys;
    if (kind != null) {
      keys = catalog.keysOf(kind);
      if (keys == null) {
        _issueAt(
          kindNode!,
          'Unknown step type "$kind".',
          hint: suggestion(kind, catalog.kinds, label: 'Known'),
        );
      }
    }
    final withNode = node.nodes['with'];
    final values = <String, Object?>{};
    if (withNode != null) {
      if (withNode is! YamlMap) {
        _issueAt(withNode, '"with" is a mapping.');
      } else {
        for (final entry in withNode.nodes.entries) {
          final key = entry.key as YamlScalar;
          final name = '${key.value}';
          final stepKey = keys?[name];
          if (keys != null && stepKey == null) {
            _issueAt(
              key,
              '"$kind" does not take "$name".',
              hint: keys.isEmpty
                  ? 'It takes nothing under "with".'
                  : suggestion(name, keys.keys, label: 'It takes'),
            );
          }
          _checkTemplates(entry.value, variables);
          values[name] = _plain(entry.value);
          if (stepKey?.problemOf(values[name]) case final problem?) {
            _issueAt(entry.value, '$problem.');
          }
        }
      }
    }
    for (final key in keys?.values ?? const <StepKey>[]) {
      if (key.required && values[key.name] == null) {
        _issueAt(withNode ?? node, '"$kind" needs "${key.name}" under "with".');
      }
    }
    final (condition, conditionText) = _condition(node, variables);
    GateAction? gate;
    final gateNode = node.nodes['gate'];
    if (gateNode != null) {
      gate = gateNode is YamlScalar && gateNode.value is String
          ? GateAction.fromWire(gateNode.value as String)
          : null;
      if (gate == null) {
        final name = gateNode is YamlScalar ? '${gateNode.value}' : '';
        _issueAt(
          gateNode,
          'Unknown gate "$name".',
          hint: suggestion(name, [
            for (final action in GateAction.values) action.wire,
          ]),
        );
      }
    }
    if (kind == null || keys == null) return null;
    return StepDefinition(
      kind: kind,
      withValues: values,
      condition: condition,
      conditionText: conditionText,
      gate: gate,
      position: _position(node),
    );
  }

  /// Checks `commitFrom` and `artifactsFrom` of the steps: each names a job of
  /// an earlier stage.
  void _checkCommitSources(List<StageDefinition> stages) {
    final earlier = <String>{};
    for (final stage in stages) {
      for (final job in stage.jobs) {
        for (final step in job.steps) {
          for (final key in const ['commitFrom', 'artifactsFrom']) {
            final source = step.withValues[key];
            if (source is String &&
                !source.contains(r'${{') &&
                !earlier.contains(source)) {
              _issue(
                step.position.line,
                step.position.column,
                '"$key" must name a job of an earlier stage, not "$source".',
              );
            }
          }
        }
      }
      earlier.addAll(stage.jobs.map((job) => job.id));
    }
  }

  // --------------------------------------------------------- expressions

  (Expression?, String?) _condition(YamlMap map, Set<String> variables) {
    final node = map.nodes['if'];
    if (node == null) return (null, null);
    if (node is YamlScalar && (node.value == null || node.value == '')) {
      // YAML reads a leading "!" as a tag, and "if: !x" as nothing.
      _issueAt(
        node,
        '"if" is empty. Quote an expression that starts with "!", as in '
        '"!flavor.prod".',
      );
      return (null, null);
    }
    final text = _text(node, '"if"');
    if (text == null) return (null, null);
    try {
      final expression = Expression.parse(text);
      _checkVariables(node, expression, variables);
      return (expression, text);
    } on ExpressionException catch (error) {
      _issueAt(node, error.message, offset: error.offset);
      return (null, null);
    }
  }

  Template? _template(YamlNode node, String text, Set<String> variables) {
    try {
      final template = Template.parse(text);
      for (final expression in template.expressions) {
        _checkVariables(node, expression, variables);
      }
      return template;
    } on ExpressionException catch (error) {
      _issueAt(node, error.message, offset: error.offset);
      return null;
    }
  }

  void _checkTemplates(YamlNode node, Set<String> variables) {
    switch (node) {
      case YamlScalar(:final value) when value is String:
        if (value.contains(r'${{')) _template(node, value, variables);
      case YamlList():
        for (final item in node.nodes) {
          _checkTemplates(item, variables);
        }
      case YamlMap():
        for (final item in node.nodes.values) {
          _checkTemplates(item, variables);
        }
      case _:
    }
  }

  void _checkVariables(
    YamlNode node,
    Expression expression,
    Set<String> variables,
  ) {
    for (final path in expression.paths) {
      final [name, ...fields] = path.split('.');
      if (!variables.contains(name)) {
        _issueAt(
          node,
          'Unknown variable "$name".',
          hint: suggestion(name, variables, label: 'Known here'),
        );
      } else if (fields.isNotEmpty) {
        _checkFields(node, name, fields);
      }
    }
  }

  /// Checks that the variable [name] has the [fields] read from it, as far as
  /// they are known: the inputs the workflow declares, the fields of
  /// `flavor`, `app` and `project`, and none for a string or a number.
  void _checkFields(YamlNode node, String name, List<String> fields) {
    final [field, ...] = fields;
    if (name == 'inputs') {
      if (!_inputNames.contains(field)) {
        _issueAt(
          node,
          'The workflow has no input "$field".',
          hint:
              suggestion(field, _inputNames, prefix: 'inputs.') ??
              'Declare it under "inputs".',
        );
      }
      return;
    }
    if (scalarVariables[name] case final holds?) {
      _issueAt(node, '"$name" is $holds; it has no "$field".');
      return;
    }
    for (final (depth, field) in fields.indexed) {
      final path = [name, ...fields.take(depth)].join('.');
      final known = variableFields[path];
      if (known == null) return;
      if (!known.contains(field)) {
        _issueAt(
          node,
          '"$path" has no "$field".',
          hint: suggestion(field, known, prefix: '$path.', label: 'It has'),
        );
        return;
      }
    }
  }

  // ---------------------------------------------------------------- basics

  void _checkKeys(YamlMap map, String where, Set<String> allowed) {
    for (final key in map.nodes.keys) {
      final name = key is YamlScalar ? '${key.value}' : '$key';
      if (!allowed.contains(name)) {
        _issueAt(
          key as YamlNode,
          'Unknown key "$name" in $where.',
          hint: suggestion(name, allowed),
        );
      }
    }
  }

  String? _requiredText(YamlMap map, String key, String where) {
    final node = map.nodes[key];
    if (node == null) {
      _issueAt(map, 'Add "$key" to $where.');
      return null;
    }
    return _text(node, '"$key"');
  }

  String? _optionalText(YamlMap map, String key) {
    final node = map.nodes[key];
    return node == null ? null : _text(node, '"$key"');
  }

  String? _text(YamlNode node, String what) {
    if (node is YamlScalar && node.value is String) {
      final text = node.value as String;
      if (text.trim().isNotEmpty) return text;
    }
    _issueAt(node, '$what must be a non-empty string.');
    return null;
  }

  static Object? _plain(YamlNode? node) => switch (node) {
    null => null,
    YamlScalar(:final value) => value,
    YamlList() => [for (final item in node.nodes) _plain(item)],
    YamlMap() => {
      for (final entry in node.nodes.entries)
        '${(entry.key as YamlScalar).value}': _plain(entry.value),
    },
    _ => null,
  };

  static SourcePosition _position(YamlNode node) =>
      SourcePosition(node.span.start.line + 1, node.span.start.column + 1);

  void _issueAt(YamlNode node, String message, {int offset = 0, String? hint}) {
    var column = node.span.start.column + 1;
    if (node is YamlScalar && offset > 0) {
      column += switch (node.style) {
        ScalarStyle.PLAIN => offset,
        ScalarStyle.SINGLE_QUOTED || ScalarStyle.DOUBLE_QUOTED => 1 + offset,
        _ => 0,
      };
    }
    _issue(node.span.start.line + 1, column, message, hint);
  }

  void _issue(int line, int column, String message, [String? hint]) =>
      issues.add(
        WorkflowIssue(line: line, column: column, message: message, hint: hint),
      );
}

import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:yaml/yaml.dart';

/// A workflow document (`schema: 1`) as the workflow builder edits it: every
/// key the engine reads, nothing it decides.
///
/// [WorkflowDocument.parse] reads the YAML the engine reads and refuses what
/// the model cannot hold (an unknown key, a list where a mapping goes);
/// [toYaml] writes it back in one canonical layout, so that
/// `WorkflowDocument.parse(document.toYaml()) == document`. Whether the
/// document is valid (step types, variables, expressions) is the engine's
/// call: `WorkflowsRepository.validate`.
class WorkflowDocument extends Equatable {
  /// Creates a document.
  const new({
    this.schema = 1,
    this.name,
    this.description,
    this.locksProject = false,
    this.inputs = const [],
    this.stages = const [],
  });

  /// Reads the workflow document [yaml].
  ///
  /// Throws a [WorkflowDocumentException] with the line and column of each
  /// part the model cannot hold.
  factory parse(String yaml) {
    final reader = _Reader();
    final document = reader.read(yaml);
    if (reader.issues.isNotEmpty) {
      throw WorkflowDocumentException(List.unmodifiable(reader.issues));
    }
    return document!;
  }

  /// The version of the document format; `null` when the document leaves it
  /// out (the engine then asks for it).
  final int? schema;

  /// What the owner calls the workflow.
  final String? name;

  /// What it is for.
  final String? description;

  /// Whether a run holds the project (`lock: project`).
  final bool locksProject;

  /// The inputs a dispatch can set.
  final List<WorkflowInput> inputs;

  /// The stages, in order.
  final List<WorkflowStage> stages;

  /// A copy with the given fields replaced. Pass a function returning
  /// `null` to clear [name] or [description].
  WorkflowDocument copyWith({
    String? Function()? name,
    String? Function()? description,
    bool? locksProject,
    List<WorkflowInput>? inputs,
    List<WorkflowStage>? stages,
  }) => WorkflowDocument(
    schema: schema,
    name: name == null ? this.name : name(),
    description: description == null ? this.description : description(),
    locksProject: locksProject ?? this.locksProject,
    inputs: inputs ?? this.inputs,
    stages: stages ?? this.stages,
  );

  /// The document as YAML, in the layout of the built-in workflows.
  String toYaml() {
    final out = StringBuffer();
    _writeMap(out, {
      'schema': ?schema,
      'name': ?name,
      'description': ?description,
      if (locksProject) 'lock': 'project',
      if (inputs.isNotEmpty)
        'inputs': {for (final input in inputs) input.name: input._plain()},
      'stages': [for (final stage in stages) stage._plain()],
    }, 0);
    return out.toString();
  }

  @override
  List<Object?> get props => [
    schema,
    name,
    description,
    locksProject,
    inputs,
    stages,
  ];
}

/// A variable a dispatch can set (`inputs.<name>`).
class WorkflowInput extends Equatable {
  /// Creates an input.
  const new({
    required this.name,
    this.description,
    this.defaultValue,
    this.required = false,
  });

  /// The name under `inputs`.
  final String name;

  /// What it is for.
  final String? description;

  /// The value when a dispatch gives none; `null` for none.
  final Object? defaultValue;

  /// Whether a dispatch must give it.
  final bool required;

  Map<String, Object?> _plain() => {
    'description': ?description,
    'default': ?defaultValue,
    if (required) 'required': true,
  };

  @override
  List<Object?> get props => [name, description, defaultValue, required];
}

/// Jobs that run at the same time, after the stage before them.
class WorkflowStage extends Equatable {
  /// Creates a stage.
  const new({required this.name, this.jobs = const []});

  /// The name of the stage.
  final String name;

  /// Its jobs, in order.
  final List<WorkflowJob> jobs;

  /// A copy with the given fields replaced.
  WorkflowStage copyWith({String? name, List<WorkflowJob>? jobs}) =>
      WorkflowStage(name: name ?? this.name, jobs: jobs ?? this.jobs);

  Map<String, Object?> _plain() => {
    'name': name,
    'jobs': {for (final job in jobs) job.id: job._plain()},
  };

  @override
  List<Object?> get props => [name, jobs];
}

/// A job: the steps one runner executes, once per cell of its matrix.
class WorkflowJob extends Equatable {
  /// Creates a job.
  const new({
    required this.id,
    this.name,
    this.matrix = const [],
    this.condition,
    this.capabilities = const [],
    this.steps = const [],
  });

  /// The key of the job, unique in the workflow.
  final String id;

  /// The name of the jobs it makes, with `${{ }}` placeholders.
  final String? name;

  /// The dimensions the job is repeated over.
  final List<WorkflowMatrixAxis> matrix;

  /// The `if` expression a cell of the matrix must meet to make a job.
  final String? condition;

  /// What a runner needs besides what the steps imply.
  final List<String> capabilities;

  /// The steps, in order.
  final List<WorkflowStep> steps;

  /// A copy with the given fields replaced. Pass a function returning
  /// `null` to clear [name] or [condition].
  WorkflowJob copyWith({
    String? id,
    String? Function()? name,
    List<WorkflowMatrixAxis>? matrix,
    String? Function()? condition,
    List<String>? capabilities,
    List<WorkflowStep>? steps,
  }) => WorkflowJob(
    id: id ?? this.id,
    name: name == null ? this.name : name(),
    matrix: matrix ?? this.matrix,
    condition: condition == null ? this.condition : condition(),
    capabilities: capabilities ?? this.capabilities,
    steps: steps ?? this.steps,
  );

  Map<String, Object?> _plain() => {
    'name': ?name,
    if (matrix.isNotEmpty)
      'matrix': {for (final axis in matrix) axis.name: axis._plain()},
    'if': ?condition,
    if (capabilities.isNotEmpty) 'capabilities': capabilities,
    'steps': [for (final step in steps) step._plain()],
  };

  @override
  List<Object?> get props => [id, name, matrix, condition, capabilities, steps];
}

/// One dimension of a job's matrix: the values written out, or a
/// placeholder that gives them at dispatch (`${{ platforms }}`).
class WorkflowMatrixAxis extends Equatable {
  /// An axis with the values [values].
  const new list(this.name, List<String> this.values) : reference = null;

  /// An axis whose values come from the placeholder [reference].
  const new placeholder(this.name, String this.reference) : values = null;

  /// `platform` or `flavor`.
  final String name;

  /// The values, when written out.
  final List<String>? values;

  /// The placeholder, when not written out.
  final String? reference;

  Object _plain() => values ?? reference!;

  @override
  List<Object?> get props => [name, values, reference];
}

/// One step of a job.
class WorkflowStep extends Equatable {
  /// Creates a step.
  const new({
    required this.kind,
    this.condition,
    this.gate,
    this.withValues = const {},
  });

  /// The step type, for example `build.android`.
  final String kind;

  /// The `if` expression the step must meet to be kept.
  final String? condition;

  /// The action the owner approves before the step runs.
  final String? gate;

  /// What the step is told: plain YAML values (strings, numbers, booleans,
  /// lists and maps) whose strings may hold `${{ }}` placeholders.
  final Map<String, Object?> withValues;

  /// A copy with the given fields replaced. Pass a function returning
  /// `null` to clear [condition] or [gate].
  WorkflowStep copyWith({
    String? kind,
    String? Function()? condition,
    String? Function()? gate,
    Map<String, Object?>? withValues,
  }) => WorkflowStep(
    kind: kind ?? this.kind,
    condition: condition == null ? this.condition : condition(),
    gate: gate == null ? this.gate : gate(),
    withValues: withValues ?? this.withValues,
  );

  Map<String, Object?> _plain() => {
    'kind': kind,
    'if': ?condition,
    'gate': ?gate,
    if (withValues.isNotEmpty) 'with': withValues,
  };

  @override
  List<Object?> get props => [kind, condition, gate, withValues];
}

/// A workflow document has parts the [WorkflowDocument] model cannot hold.
class WorkflowDocumentException implements Exception {
  /// Creates the exception.
  const new(this.issues);

  /// Where the parts are, in the order of the document.
  final List<WorkflowIssue> issues;

  @override
  String toString() => 'WorkflowDocumentException: ${issues.join(' ')}';
}

/// [value] as one line of YAML (flow style), for a field of the builder.
/// [parseYamlValue] reads it back.
String formatYamlValue(Object? value) =>
    value is String && _isPlain(value) ? value : _flow(value);

/// The plain value the YAML [text] stands for; [text] itself when it is not
/// YAML, and `''` when it is blank.
Object? parseYamlValue(String text) {
  if (text.trim().isEmpty) return '';
  try {
    return _plainOf(loadYaml(text));
  } on YamlException {
    return text;
  }
}

// ------------------------------------------------------------------- reader

class _Reader {
  final issues = <WorkflowIssue>[];

  WorkflowDocument? read(String source) {
    final YamlNode root;
    try {
      root = loadYamlNode(source);
    } on YamlException catch (error) {
      final start = error.span?.start;
      issues.add(
        WorkflowIssue(
          line: (start?.line ?? 0) + 1,
          column: (start?.column ?? 0) + 1,
          message: 'The document is not valid YAML: ${error.message}',
        ),
      );
      return null;
    }
    if (root is! YamlMap) {
      _issue(root, 'A workflow is a mapping with "schema" and "stages".');
      return null;
    }
    _keys(root, 'the workflow', const {
      'schema',
      'name',
      'description',
      'lock',
      'inputs',
      'stages',
    });
    final schemaNode = root.nodes['schema'];
    int? schema;
    if (schemaNode is YamlScalar && schemaNode.value is int) {
      schema = schemaNode.value as int;
    } else if (schemaNode != null) {
      _issue(schemaNode, '"schema" is a number.');
    }
    final lock = root.nodes['lock'];
    if (lock != null && !(lock is YamlScalar && lock.value == 'project')) {
      _issue(lock, '"lock" can only be "project".');
    }
    return WorkflowDocument(
      schema: schema,
      name: _text(root, 'name'),
      description: _text(root, 'description'),
      locksProject: lock != null,
      inputs: [
        for (final MapEntry(:key, :value) in _map(root, 'inputs').entries)
          ?_input(key, value),
      ],
      stages: [for (final node in _list(root, 'stages')) ?_stage(node)],
    );
  }

  WorkflowInput? _input(String name, YamlNode node) {
    if (node is YamlScalar && node.value == null) {
      return WorkflowInput(name: name);
    }
    if (node is! YamlMap) {
      _issue(node, 'An input is a mapping, or empty.');
      return null;
    }
    _keys(node, 'input "$name"', const {'description', 'default', 'required'});
    final required = node.nodes['required'];
    if (required != null &&
        !(required is YamlScalar && required.value is bool)) {
      _issue(required, '"required" is true or false.');
    }
    return WorkflowInput(
      name: name,
      description: _text(node, 'description'),
      defaultValue: _plainOf(node.nodes['default']),
      required: required?.value == true,
    );
  }

  WorkflowStage? _stage(YamlNode node) {
    if (node is! YamlMap) {
      _issue(node, 'A stage is a mapping with "name" and "jobs".');
      return null;
    }
    _keys(node, 'a stage', const {'name', 'jobs'});
    return WorkflowStage(
      name: _text(node, 'name') ?? '',
      jobs: [
        for (final MapEntry(:key, :value) in _map(node, 'jobs').entries)
          ?_job(key, value),
      ],
    );
  }

  WorkflowJob? _job(String id, YamlNode node) {
    if (node is! YamlMap) {
      _issue(node, 'A job is a mapping with "steps".');
      return null;
    }
    _keys(node, 'job "$id"', const {
      'name',
      'matrix',
      'if',
      'capabilities',
      'steps',
    });
    return WorkflowJob(
      id: id,
      name: _text(node, 'name'),
      matrix: [
        for (final MapEntry(:key, :value) in _map(node, 'matrix').entries)
          ?_axis(key, value),
      ],
      condition: _condition(node),
      capabilities: _stringItems(_list(node, 'capabilities')),
      steps: [for (final step in _list(node, 'steps')) ?_step(step)],
    );
  }

  WorkflowMatrixAxis? _axis(String name, YamlNode node) {
    if (node is YamlScalar && node.value is String) {
      return WorkflowMatrixAxis.placeholder(name, node.value as String);
    }
    if (node is YamlList) {
      return WorkflowMatrixAxis.list(name, _stringItems(node.nodes));
    }
    _issue(
      node,
      'A matrix axis is a list of values or a placeholder such as '
      r'${{ platforms }}.',
    );
    return null;
  }

  WorkflowStep? _step(YamlNode node) {
    if (node is! YamlMap) {
      _issue(node, 'A step is a mapping with a "kind".');
      return null;
    }
    _keys(node, 'a step', const {'kind', 'with', 'if', 'gate'});
    final kind = _text(node, 'kind');
    if (kind == null) _issue(node, 'Add "kind" to the step.');
    return WorkflowStep(
      kind: kind ?? '',
      condition: _condition(node),
      gate: _text(node, 'gate'),
      withValues: {
        for (final MapEntry(:key, :value) in _map(node, 'with').entries)
          key: _plainOf(value),
      },
    );
  }

  /// The `if` of [map]. YAML reads `if: !x` as a tag on nothing; like the
  /// engine, an empty `if` is refused.
  String? _condition(YamlMap map) {
    final node = map.nodes['if'];
    if (node is YamlScalar && (node.value == null || node.value == '')) {
      _issue(
        node,
        '"if" is empty. Quote an expression that starts with "!", as in '
        '"!flavor.prod".',
      );
      return null;
    }
    return _text(map, 'if');
  }

  // ---------------------------------------------------------------- shapes

  void _keys(YamlMap map, String where, Set<String> allowed) {
    for (final key in map.nodes.keys.cast<YamlNode>()) {
      final name = '${key.value}';
      if (!allowed.contains(name)) {
        _issue(
          key,
          'Unknown key "$name" in $where. Allowed: '
          '${(allowed.toList()..sort()).join(', ')}.',
        );
      }
    }
  }

  /// The text under [key], `null` when it is missing or empty.
  String? _text(YamlMap map, String key) {
    final node = map.nodes[key];
    if (node == null || (node is YamlScalar && node.value == null)) {
      return null;
    }
    if (node is YamlScalar && node.value is String) {
      return node.value as String;
    }
    _issue(node, '"$key" is text.');
    return null;
  }

  Map<String, YamlNode> _map(YamlMap map, String key) {
    final node = map.nodes[key];
    if (node == null || (node is YamlScalar && node.value == null)) {
      return const {};
    }
    if (node is! YamlMap) {
      _issue(node, '"$key" is a mapping.');
      return const {};
    }
    return {
      for (final MapEntry(:key, :value) in node.nodes.entries)
        '${(key as YamlNode).value}': value,
    };
  }

  List<YamlNode> _list(YamlMap map, String key) {
    final node = map.nodes[key];
    if (node == null || (node is YamlScalar && node.value == null)) {
      return const [];
    }
    if (node is! YamlList) {
      _issue(node, '"$key" is a list.');
      return const [];
    }
    return node.nodes;
  }

  List<String> _stringItems(List<YamlNode> nodes) => [
    for (final item in nodes)
      if (item is YamlScalar && item.value is String)
        item.value as String
      else
        ?_refuse(item, 'A value here is text.'),
  ];

  String? _refuse(YamlNode node, String message) {
    _issue(node, message);
    return null;
  }

  void _issue(YamlNode node, String message) => issues.add(
    WorkflowIssue(
      line: node.span.start.line + 1,
      column: node.span.start.column + 1,
      message: message,
    ),
  );
}

/// [value] with YAML nodes, maps and lists turned into plain Dart ones.
Object? _plainOf(Object? value) => switch (value) {
  final YamlScalar scalar => scalar.value,
  final Map<Object?, Object?> map => <String, Object?>{
    for (final MapEntry(:key, :value) in map.entries)
      '${key is YamlNode ? key.value : key}': _plainOf(value),
  },
  final List<Object?> list => [for (final item in list) _plainOf(item)],
  _ => value,
};

// ------------------------------------------------------------------- writer

/// Lists this short, of scalars, are written on one line: `[a, b]`.
const _flowWidth = 72;

void _writeMap(StringBuffer out, Map<String, Object?> map, int indent) {
  for (final MapEntry(:key, :value) in map.entries) {
    out.write('${' ' * indent}${_key(key)}:');
    _writeValue(out, value, indent);
  }
}

/// Writes [value] after a `key:` (or `-`) at [indent], with its line break.
void _writeValue(StringBuffer out, Object? value, int indent) {
  switch (value) {
    case final Map<String, Object?> map when map.isNotEmpty:
      out.writeln();
      _writeMap(out, map, indent + 2);
    case final List<Object?> list when list.isNotEmpty && !_flowable(list):
      out.writeln();
      _writeList(out, list, indent + 2);
    case final String text when text.contains('\n'):
      out.writeln(' ${_multiline(text, indent + 2)}');
    case _:
      out.writeln(' ${formatYamlValue(value)}');
  }
}

void _writeList(StringBuffer out, List<Object?> list, int indent) {
  for (final item in list) {
    if (item case final Map<String, Object?> map when map.isNotEmpty) {
      final MapEntry(:key, :value) = map.entries.first;
      out.write('${' ' * indent}- ${_key(key)}:');
      _writeValue(out, value, indent + 2);
      _writeMap(out, Map.fromEntries(map.entries.skip(1)), indent + 2);
    } else {
      out.write('${' ' * indent}-');
      _writeValue(out, item, indent);
    }
  }
}

bool _flowable(List<Object?> list) =>
    list.every(
      (item) =>
          item is! Map &&
          item is! List &&
          !(item is String && item.contains('\n')),
    ) &&
    _flow(list).length <= _flowWidth;

String _key(String key) => _isPlain(key) ? key : _quoted(key);

/// [value] in flow style: one line, safe inside `[...]` and `{...}`.
String _flow(Object? value) => switch (value) {
  null => 'null',
  final String text when text.contains('\n') || text.contains('\r') =>
    jsonEncode(text),
  final String text when _isPlain(text) && !text.contains(_flowIndicator) =>
    text,
  final String text => _quoted(text),
  final Map<String, Object?> map =>
    '{${map.entries.map(_flowEntry).join(', ')}}',
  final List<Object?> list => '[${list.map(_flow).join(', ')}]',
  _ => '$value',
};

String _flowEntry(MapEntry<String, Object?> entry) {
  final key = entry.key;
  final plain = _isPlain(key) && !key.contains(_flowIndicator);
  return '${plain ? key : _quoted(key)}: ${_flow(entry.value)}';
}

final _flowIndicator = RegExp(r'[,\[\]{}]');

String _quoted(String text) => text.contains('\n') || text.contains('\r')
    ? jsonEncode(text)
    : "'${text.replaceAll("'", "''")}'";

/// Whether [text] reads back as itself when written without quotes.
bool _isPlain(String text) {
  if (text.isEmpty || text.trim() != text || text.contains('\n')) {
    return false;
  }
  return _tryLoad(text) == text;
}

/// The value of the YAML [source], `null` when it does not parse.
Object? _tryLoad(String source) {
  try {
    return loadYaml(source);
  } on YamlException {
    return null;
  }
}

/// [text], which has line breaks, as a literal block (`|`) whose lines sit
/// at [indent]; JSON-style double quotes when a block cannot hold it as is.
String _multiline(String text, int indent) {
  final body = text.endsWith('\n') ? text.substring(0, text.length - 1) : text;
  final header = text.endsWith('\n') ? '|' : '|-';
  final pad = ' ' * indent;
  final block = [
    header,
    for (final line in body.split('\n'))
      if (line.isEmpty) '' else '$pad$line',
  ].join('\n');
  final back = _tryLoad('x: $block\n');
  return back is Map && back['x'] == text ? block : jsonEncode(text);
}

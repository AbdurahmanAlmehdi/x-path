import 'package:equatable/equatable.dart';
import 'package:yaml/yaml.dart';

/// What the app reads of a workflow document: its stages, their jobs and
/// their steps, enough to name the stages of a run and to preview a
/// dispatch. The engine validates and plans the document; this reads it
/// leniently and never decides what runs.
class WorkflowOutline extends Equatable {
  /// Creates an outline.
  const new({
    this.name,
    this.locksProject = false,
    this.inputDefaults = const {},
    this.stages = const [],
  });

  /// Reads the outline of the workflow document [yaml]. Parts it does not
  /// understand are left out.
  ///
  /// Throws a [FormatException] when [yaml] is not a YAML mapping.
  factory parse(String yaml) {
    final Object? document;
    try {
      document = _plain(loadYaml(yaml));
    } on YamlException catch (error) {
      throw FormatException(error.message);
    }
    if (document is! Map<String, Object?>) {
      throw const FormatException('A workflow is a YAML mapping.');
    }
    return WorkflowOutline(
      name: _string(document['name']),
      locksProject: document['lock'] == 'project',
      inputDefaults: {
        for (final MapEntry(:key, :value) in _map(document['inputs']).entries)
          key: _map(value)['default'],
      },
      stages: [
        for (final stage in _list(document['stages']))
          if (stage is Map<String, Object?>) StageOutline._read(stage),
      ],
    );
  }

  /// The name the workflow gives itself.
  final String? name;

  /// Whether a run holds the project (`lock: project`): a production release
  /// or patch.
  final bool locksProject;

  /// The default of each input it declares.
  final Map<String, Object?> inputDefaults;

  /// The stages, in order.
  final List<StageOutline> stages;

  @override
  List<Object?> get props => [name, locksProject, inputDefaults, stages];
}

/// One stage of a [WorkflowOutline].
class StageOutline extends Equatable {
  /// Creates a stage.
  const new({required this.name, this.jobs = const []});

  factory _read(Map<String, Object?> stage) => StageOutline(
    name: _string(stage['name']) ?? '',
    jobs: [
      for (final MapEntry(:key, :value) in _map(stage['jobs']).entries)
        if (value is Map<String, Object?>) JobOutline._read(key, value),
    ],
  );

  /// The stage's name, for example `build`.
  final String name;

  /// Its jobs, in the order written.
  final List<JobOutline> jobs;

  @override
  List<Object?> get props => [name, jobs];
}

/// One job of a [StageOutline], before its matrix is expanded.
class JobOutline extends Equatable {
  /// Creates a job.
  const new({
    required this.id,
    this.name,
    this.matrix = const {},
    this.condition,
    this.capabilities = const [],
    this.steps = const [],
  });

  factory _read(String id, Map<String, Object?> job) => JobOutline(
    id: id,
    name: _string(job['name']),
    matrix: _map(job['matrix']),
    condition: _string(job['if']),
    capabilities: [..._list(job['capabilities']).whereType<String>()],
    steps: [
      for (final step in _list(job['steps']))
        if (step is Map<String, Object?> && step['kind'] is String)
          StepOutline(
            kind: step['kind']! as String,
            condition: _string(step['if']),
            gate: _string(step['gate']),
          ),
    ],
  );

  /// The job's id in the workflow.
  final String id;

  /// The name template of the jobs it makes, with `${{ }}` placeholders.
  final String? name;

  /// The matrix: each axis (`platform`, `flavor`) and its values, a list or a
  /// `${{ }}` reference.
  final Map<String, Object?> matrix;

  /// The `if` expression a matrix cell must meet to make a job.
  final String? condition;

  /// The capabilities the job declares it needs besides those of its steps.
  final List<String> capabilities;

  /// Its steps, in order.
  final List<StepOutline> steps;

  @override
  List<Object?> get props => [id, name, matrix, condition, capabilities, steps];
}

/// One step of a [JobOutline].
class StepOutline extends Equatable {
  /// Creates a step.
  const new({required this.kind, this.condition, this.gate});

  /// The step type, for example `build.ios`.
  final String kind;

  /// The `if` expression the step must meet to run.
  final String? condition;

  /// The gated action in front of the step (`prod_release`, `push`, ...).
  final String? gate;

  @override
  List<Object?> get props => [kind, condition, gate];
}

/// [value] with YAML maps and lists turned into plain Dart ones.
Object? _plain(Object? value) => switch (value) {
  final YamlMap map => <String, Object?>{
    for (final MapEntry(:key, :value) in map.entries) '$key': _plain(value),
  },
  final YamlList list => [for (final item in list) _plain(item)],
  _ => value,
};

String? _string(Object? value) => value is String ? value : null;

Map<String, Object?> _map(Object? value) =>
    value is Map<String, Object?> ? value : const {};

List<Object?> _list(Object? value) => value is List<Object?> ? value : const [];

import 'package:equatable/equatable.dart';
import 'package:xp_engine/src/scheduler/capability.dart';
import 'package:xp_engine/src/workflows/expression.dart';
import 'package:xp_engine/src/workflows/gate_action.dart';

/// The version of the workflow document this engine reads (`schema: 1`).
const workflowSchemaVersion = 1;

/// The variables a workflow can read, besides the ones its matrix defines.
///
/// `inputs` holds the values of the inputs the workflow declares; the rest
/// come from the dispatch (see `WorkflowDispatcher`).
const dispatchVariables = {
  'app',
  'bump',
  'build',
  'flavors',
  'inputs',
  'patch',
  'platforms',
  'project',
  'ref',
  'release',
  'releaseVersion',
  'sha',
  'version',
};

/// The dimensions a job can multiply itself over, and the values `platform`
/// can take.
const matrixAxes = ['platform', 'flavor'];

/// `android` and `ios`.
const platformNames = ['android', 'ios'];

/// A place in the workflow document, from 1.
class SourcePosition extends Equatable {
  /// Creates a position.
  const new(this.line, this.column);

  /// The line.
  final int line;

  /// The column.
  final int column;

  @override
  String toString() => '$line:$column';

  @override
  List<Object?> get props => [line, column];
}

/// An input the owner gives when dispatching: a variable of the workflow
/// (`inputs.notes`), with a default.
class InputDefinition extends Equatable {
  /// Creates the definition.
  const new({
    required this.name,
    required this.position,
    this.description,
    this.defaultValue,
    this.required = false,
  });

  /// The name under `inputs`.
  final String name;

  /// What it is for.
  final String? description;

  /// The value when the dispatch gives none. Plain data: strings, numbers,
  /// booleans, lists and maps.
  final Object? defaultValue;

  /// Whether a dispatch without it is refused (and has no default).
  final bool required;

  /// Where it is declared.
  final SourcePosition position;

  @override
  List<Object?> get props => [
    name,
    description,
    defaultValue,
    required,
    position,
  ];
}

/// One dimension of the matrix of a job: the values it takes, written out or
/// read from a dispatch variable (`${{ platforms }}`).
class MatrixAxis extends Equatable {
  /// Creates an axis.
  const new({
    required this.name,
    required this.position,
    this.values,
    this.reference,
  }) : assert(
         (values == null) != (reference == null),
         'An axis has values or a reference.',
       );

  /// `platform` or `flavor`.
  final String name;

  /// The values, when written out.
  final List<String>? values;

  /// The placeholder that gives the values, when not written out.
  final Template? reference;

  /// Where it is written.
  final SourcePosition position;

  @override
  List<Object?> get props => [name, values, position];
}

/// One step of a job, as the workflow writes it.
class StepDefinition {
  /// Creates the definition.
  const new({
    required this.kind,
    required this.position,
    this.withValues = const {},
    this.condition,
    this.conditionText,
    this.gate,
  });

  /// The step type, for example `build.android`.
  final String kind;

  /// What the step is told: the keys the step type takes, with plain values
  /// whose strings may hold `${{ }}` placeholders.
  final Map<String, Object?> withValues;

  /// The step is left out when this is false for the job. Evaluated when the
  /// workflow is dispatched, not when the job runs.
  final Expression? condition;

  /// The text of [condition].
  final String? conditionText;

  /// The action the owner approves before the step runs (D-13).
  final GateAction? gate;

  /// Where the step starts.
  final SourcePosition position;
}

/// A job: the steps one runner executes, once for each cell of its matrix.
class JobDefinition {
  /// Creates the definition.
  const new({
    required this.id,
    required this.steps,
    required this.position,
    this.name,
    this.matrix = const [],
    this.condition,
    this.capabilities = const [],
  });

  /// The key of the job in its stage. Unique in the workflow.
  final String id;

  /// The name of a job made from this definition; `id` with the matrix
  /// values by default.
  final Template? name;

  /// The dimensions the job is repeated over.
  final List<MatrixAxis> matrix;

  /// A cell of the matrix makes no job when this is false for it.
  final Expression? condition;

  /// What a runner needs besides what the steps imply.
  final List<Capability> capabilities;

  /// The steps, in order.
  final List<StepDefinition> steps;

  /// Where the job starts.
  final SourcePosition position;
}

/// Jobs that may run at the same time. A stage starts when every job of the
/// stage before it succeeded.
class StageDefinition {
  /// Creates the definition.
  const new({required this.name, required this.jobs, required this.position});

  /// The name of the stage.
  final String name;

  /// Its jobs, in the order of the document.
  final List<JobDefinition> jobs;

  /// Where the stage starts.
  final SourcePosition position;
}

/// A workflow document, read and checked.
class WorkflowDefinition {
  /// Creates the definition.
  const new({
    required this.stages,
    this.name,
    this.description,
    this.locksProject = false,
    this.inputs = const [],
  });

  /// What the owner calls it, if the document says.
  final String? name;

  /// What it is for.
  final String? description;

  /// Whether a run holds the project: one run of such a workflow at a time
  /// (D-11), for production releases and patches.
  final bool locksProject;

  /// The inputs a dispatch can set.
  final List<InputDefinition> inputs;

  /// The stages, in order.
  final List<StageDefinition> stages;

  /// Every job definition, in the order of the document.
  Iterable<JobDefinition> get jobs => stages.expand((stage) => stage.jobs);
}

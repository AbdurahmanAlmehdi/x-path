import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_repositories/xp_repositories.dart';

/// What the builder's inspector shows: the workflow itself ([stage] `null`),
/// a stage ([job] `null`) or a job of a stage.
class WorkflowSelection extends Equatable {
  const new({this.stage, this.job});

  /// The workflow's own fields: name, description, lock.
  static const workflow = WorkflowSelection();

  final int? stage;
  final int? job;

  /// This selection, or the nearest one that [document] still has.
  WorkflowSelection within(WorkflowDocument document) {
    final stage = this.stage;
    if (stage == null || document.stages.isEmpty) return workflow;
    final s = stage.clamp(0, document.stages.length - 1);
    final jobs = document.stages[s].jobs;
    final job = this.job;
    if (job == null || jobs.isEmpty) return WorkflowSelection(stage: s);
    return WorkflowSelection(stage: s, job: job.clamp(0, jobs.length - 1));
  }

  @override
  List<Object?> get props => [stage, job];
}

/// The edits of the visual builder. Each returns a new document; the one it
/// is called on is left as it was.
extension WorkflowEdits on WorkflowDocument {
  /// Adds a stage called [name] with one empty job at the end.
  WorkflowDocument addStage(String name) => copyWith(
    stages: [
      ...stages,
      WorkflowStage(
        name: name,
        jobs: [WorkflowJob(id: uniqueJobId(name))],
      ),
    ],
  );

  /// Replaces stage [index] with what [edit] makes of it.
  WorkflowDocument editStage(
    int index,
    WorkflowStage Function(WorkflowStage stage) edit,
  ) => copyWith(stages: _replaced(stages, index, edit(stages[index])));

  WorkflowDocument removeStage(int index) =>
      copyWith(stages: [...stages]..removeAt(index));

  /// Moves stage [index] by [delta] places (`-1` earlier, `1` later).
  WorkflowDocument moveStage(int index, int delta) =>
      copyWith(stages: _moved(stages, index, delta));

  /// Adds an empty job to stage [stage], with an id no other job has.
  WorkflowDocument addJob(int stage) => editStage(
    stage,
    (s) => s.copyWith(
      jobs: [
        ...s.jobs,
        WorkflowJob(id: uniqueJobId(s.name)),
      ],
    ),
  );

  /// Replaces job [job] of stage [stage] with what [edit] makes of it.
  WorkflowDocument editJob(
    int stage,
    int job,
    WorkflowJob Function(WorkflowJob job) edit,
  ) => editStage(
    stage,
    (s) => s.copyWith(jobs: _replaced(s.jobs, job, edit(s.jobs[job]))),
  );

  WorkflowDocument removeJob(int stage, int job) =>
      editStage(stage, (s) => s.copyWith(jobs: [...s.jobs]..removeAt(job)));

  WorkflowDocument moveJob(int stage, int job, int delta) =>
      editStage(stage, (s) => s.copyWith(jobs: _moved(s.jobs, job, delta)));

  /// Adds an input with a name no other input has, without a type.
  WorkflowDocument addInput() {
    final used = {for (final input in inputs) input.name};
    var name = 'input';
    for (var n = 2; used.contains(name); n++) {
      name = 'input$n';
    }
    return copyWith(
      inputs: [
        ...inputs,
        WorkflowInput(name: name),
      ],
    );
  }

  /// Replaces input [index] with what [edit] makes of it.
  WorkflowDocument editInput(
    int index,
    WorkflowInput Function(WorkflowInput input) edit,
  ) => copyWith(inputs: _replaced(inputs, index, edit(inputs[index])));

  WorkflowDocument removeInput(int index) =>
      copyWith(inputs: [...inputs]..removeAt(index));

  /// [base], or `base-2`, `base-3`… whichever no job of the workflow uses.
  String uniqueJobId(String base) {
    final used = {
      for (final stage in stages)
        for (final job in stage.jobs) job.id,
    };
    final stem = base.isEmpty ? 'job' : base;
    if (!used.contains(stem)) return stem;
    var n = 2;
    while (used.contains('$stem-$n')) {
      n++;
    }
    return '$stem-$n';
  }
}

/// An input with some of its fields changed; a `null` function keeps one.
extension WorkflowInputEdits on WorkflowInput {
  WorkflowInput copyWith({
    String? name,
    InputType? Function()? type,
    String? Function()? description,
    List<String>? Function()? options,
    Object? Function()? defaultValue,
    bool? required,
  }) => WorkflowInput(
    name: name ?? this.name,
    type: type == null ? this.type : type(),
    description: description == null ? this.description : description(),
    options: options == null ? this.options : options(),
    defaultValue: defaultValue == null ? this.defaultValue : defaultValue(),
    required: required ?? this.required,
  );
}

/// The step edits of a job.
extension WorkflowJobEdits on WorkflowJob {
  WorkflowJob addStep(String kind) => copyWith(
    steps: [
      ...steps,
      WorkflowStep(kind: kind),
    ],
  );

  WorkflowJob editStep(
    int index,
    WorkflowStep Function(WorkflowStep step) edit,
  ) => copyWith(steps: _replaced(steps, index, edit(steps[index])));

  WorkflowJob removeStep(int index) =>
      copyWith(steps: [...steps]..removeAt(index));

  WorkflowJob moveStep(int index, int delta) =>
      copyWith(steps: _moved(steps, index, delta));

  /// The job with the matrix axis [name] set to [axis], or without it when
  /// [axis] is `null`. A new axis goes after the others.
  WorkflowJob withAxis(String name, WorkflowMatrixAxis? axis) {
    final index = matrix.indexWhere((a) => a.name == name);
    if (axis == null) {
      return index < 0 ? this : copyWith(matrix: [...matrix]..removeAt(index));
    }
    return copyWith(
      matrix: index < 0 ? [...matrix, axis] : _replaced(matrix, index, axis),
    );
  }

  /// The axis called [name], if the job has one.
  WorkflowMatrixAxis? axis(String name) =>
      matrix.where((a) => a.name == name).firstOrNull;
}

List<T> _replaced<T>(List<T> list, int index, T value) =>
    [...list]..[index] = value;

List<T> _moved<T>(List<T> list, int index, int delta) {
  final to = index + delta;
  if (to < 0 || to >= list.length) return list;
  final copy = [...list];
  copy.insert(to, copy.removeAt(index));
  return copy;
}

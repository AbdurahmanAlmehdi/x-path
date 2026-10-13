// `json_serializable` cannot parse `factory .name` constructors yet.
// ignore_for_file: unnecessary_type_name_in_constructor

import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'job.g.dart';

/// Where a job is in its life.
@JsonEnum(valueField: 'wire')
enum JobState {
  /// Created, not started.
  queued('queued'),

  /// A step is running.
  running('running'),

  /// Every step succeeded or was skipped.
  succeeded('succeeded'),

  /// A step failed. Resuming re-runs it.
  failed('failed'),

  /// Cancelled by a client.
  cancelled('cancelled'),

  /// The engine stopped while the job ran (D-18). Resuming re-runs the step
  /// that was running.
  interrupted('interrupted'),

  /// The engine stopped in the middle of a step with side effects, which it
  /// never repeats by itself (D-18). It waits for an explicit resume.
  waitingForResume('waiting_for_resume');

  new(this.wire);

  /// The name on the wire and in the database.
  final String wire;

  /// Whether the job has ended for good, without a resume.
  bool get isFinished =>
      this == JobState.succeeded ||
      this == JobState.failed ||
      this == JobState.cancelled;
}

/// Where a step of a job is in its life.
enum StepState {
  /// Not started.
  pending,

  /// Running now.
  running,

  /// Done.
  succeeded,

  /// Ended in failure.
  failed,

  /// Not needed: it did not apply, or it had been done already.
  skipped,

  /// Stopped by a cancel.
  cancelled,

  /// The engine stopped while it ran.
  interrupted;

  /// Whether a resume moves past this step without running it.
  bool get isDone => this == StepState.succeeded || this == StepState.skipped;
}

/// One step of a [Job].
@JsonSerializable(includeIfNull: false)
class JobStep extends Equatable {
  /// Creates a step.
  const new({
    required this.ordinal,
    required this.kind,
    required this.state,
    required this.sideEffect,
    required this.attempts,
    this.result,
    this.message,
    this.startedAt,
    this.finishedAt,
  });

  /// Reads a step from its JSON form.
  factory JobStep.fromJson(Map<String, dynamic> json) =>
      _$JobStepFromJson(json);

  /// Position in the job, from 0.
  final int ordinal;

  /// The step type, for example `command`.
  final String kind;

  /// Where it is.
  final StepState state;

  /// Whether it changes something outside the engine, which the engine never
  /// repeats without being told to (D-18).
  final bool sideEffect;

  /// How many times it was started.
  final int attempts;

  /// What it produced, once it succeeded.
  final Map<String, dynamic>? result;

  /// Why it failed or was skipped.
  final String? message;

  /// When it was last started, in UTC.
  final DateTime? startedAt;

  /// When it last ended, in UTC.
  final DateTime? finishedAt;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$JobStepToJson(this);

  @override
  List<Object?> get props => [
    ordinal,
    kind,
    state,
    sideEffect,
    attempts,
    result,
    message,
    startedAt,
    finishedAt,
  ];
}

/// A run of a workflow, with its steps.
@JsonSerializable(explicitToJson: true, includeIfNull: false)
class Job extends Equatable {
  /// Creates a job.
  const new({
    required this.id,
    required this.projectId,
    required this.workflowVersionId,
    required this.state,
    required this.createdAt,
    required this.steps,
    this.releaseId,
    this.sha,
    this.runnerId,
    this.message,
    this.startedAt,
    this.finishedAt,
  });

  /// Reads a job from its JSON form.
  factory Job.fromJson(Map<String, dynamic> json) => _$JobFromJson(json);

  /// The engine's id, for example `job_1a2b3c4d5e6f7a8b`.
  final String id;

  /// The project it runs for.
  final String projectId;

  /// The workflow version it runs.
  final String workflowVersionId;

  /// The release it produces, if any.
  final String? releaseId;

  /// The commit it builds.
  final String? sha;

  /// Where it is.
  final JobState state;

  /// The runner executing it, or `null` for the engine itself.
  final String? runnerId;

  /// Why it failed or was cancelled.
  final String? message;

  /// When it was created, in UTC.
  final DateTime createdAt;

  /// When it last started running, in UTC.
  final DateTime? startedAt;

  /// When it ended, in UTC.
  final DateTime? finishedAt;

  /// Its steps, in order.
  final List<JobStep> steps;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$JobToJson(this);

  @override
  List<Object?> get props => [
    id,
    projectId,
    workflowVersionId,
    releaseId,
    sha,
    state,
    runnerId,
    message,
    createdAt,
    startedAt,
    finishedAt,
    steps,
  ];
}

/// The body of `POST /jobs/{id}/resume`.
@JsonSerializable(includeIfNull: false, checked: true)
class ResumeJobRequest extends Equatable {
  /// Creates a request.
  const new({this.fromStep});

  /// Reads a request from its JSON form.
  factory ResumeJobRequest.fromJson(Map<String, dynamic> json) =>
      _$ResumeJobRequestFromJson(json);

  /// Re-run from the step with this ordinal, even if it and later steps
  /// succeeded. Without it the job resumes at its first unfinished step.
  final int? fromStep;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$ResumeJobRequestToJson(this);

  @override
  List<Object?> get props => [fromStep];
}

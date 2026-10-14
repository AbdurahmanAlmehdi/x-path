import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';

const _unset = Object();

/// What the engine stores about a job.
class JobRecord extends Equatable {
  /// Creates a record.
  const new({
    required this.id,
    required this.workflowVersionId,
    required this.projectId,
    required this.state,
    required this.createdAt,
    this.releaseId,
    this.sha,
    this.runnerId,
    this.runId,
    this.stage = 0,
    this.name,
    this.capabilities = const [],
    this.message,
    this.startedAt,
    this.finishedAt,
  });

  /// The engine's id.
  final String id;

  /// The workflow version it runs.
  final String workflowVersionId;

  /// The project it runs for.
  final String projectId;

  /// The release it produces, if any.
  final String? releaseId;

  /// The commit it builds.
  final String? sha;

  /// Where it is.
  final JobState state;

  /// The runner executing it, or `null` for the engine.
  final String? runnerId;

  /// The run (one dispatch of a workflow) it belongs to, or `null` for a job
  /// that was not dispatched.
  final String? runId;

  /// Its stage in the run, from 0.
  final int stage;

  /// What the workflow calls it.
  final String? name;

  /// The capabilities a runner needs to run it, by their wire names.
  final List<String> capabilities;

  /// Why it failed or was cancelled, or why a queued job still waits.
  final String? message;

  /// When it was created.
  final DateTime createdAt;

  /// When it last started running.
  final DateTime? startedAt;

  /// When it ended.
  final DateTime? finishedAt;

  /// This record with the given fields replaced. Pass `null` to [message],
  /// [startedAt] or [finishedAt] to clear them.
  JobRecord copyWith({
    JobState? state,
    Object? message = _unset,
    Object? startedAt = _unset,
    Object? finishedAt = _unset,
  }) => JobRecord(
    id: id,
    workflowVersionId: workflowVersionId,
    projectId: projectId,
    releaseId: releaseId,
    sha: sha,
    state: state ?? this.state,
    runnerId: runnerId,
    runId: runId,
    stage: stage,
    name: name,
    capabilities: capabilities,
    message: identical(message, _unset) ? this.message : message as String?,
    createdAt: createdAt,
    startedAt: identical(startedAt, _unset)
        ? this.startedAt
        : startedAt as DateTime?,
    finishedAt: identical(finishedAt, _unset)
        ? this.finishedAt
        : finishedAt as DateTime?,
  );

  @override
  List<Object?> get props => [
    id,
    workflowVersionId,
    projectId,
    releaseId,
    sha,
    state,
    runnerId,
    runId,
    stage,
    name,
    capabilities,
    message,
    createdAt,
    startedAt,
    finishedAt,
  ];
}

/// What the engine stores about one step of a job.
class StepRecord extends Equatable {
  /// Creates a record.
  const new({
    required this.jobId,
    required this.ordinal,
    required this.kind,
    required this.sideEffect,
    required this.input,
    this.state = StepState.pending,
    this.attempts = 0,
    this.result,
    this.message,
    this.pgid,
    this.logPath,
    this.startedAt,
    this.finishedAt,
  });

  /// The job it belongs to.
  final String jobId;

  /// Its position in the job, from 0.
  final int ordinal;

  /// The step type.
  final String kind;

  /// Whether it has side effects (D-18).
  final bool sideEffect;

  /// The input, as the step encoded it.
  final Map<String, dynamic> input;

  /// Where it is.
  final StepState state;

  /// How many times it was started.
  final int attempts;

  /// What it produced.
  final Map<String, dynamic>? result;

  /// Why it failed or was skipped.
  final String? message;

  /// The process group of the process it is running, recorded so that a
  /// restarted engine can stop it (ADR 0003). `null` when none runs.
  final int? pgid;

  /// The path of its log file.
  final String? logPath;

  /// When it was last started.
  final DateTime? startedAt;

  /// When it last ended.
  final DateTime? finishedAt;

  /// This record with the given fields replaced. Pass `null` to [result],
  /// [message], [pgid], [logPath], [startedAt] or [finishedAt] to clear them.
  StepRecord copyWith({
    StepState? state,
    int? attempts,
    Object? result = _unset,
    Object? message = _unset,
    Object? pgid = _unset,
    Object? logPath = _unset,
    Object? startedAt = _unset,
    Object? finishedAt = _unset,
  }) => StepRecord(
    jobId: jobId,
    ordinal: ordinal,
    kind: kind,
    sideEffect: sideEffect,
    input: input,
    state: state ?? this.state,
    attempts: attempts ?? this.attempts,
    result: identical(result, _unset)
        ? this.result
        : result as Map<String, dynamic>?,
    message: identical(message, _unset) ? this.message : message as String?,
    pgid: identical(pgid, _unset) ? this.pgid : pgid as int?,
    logPath: identical(logPath, _unset) ? this.logPath : logPath as String?,
    startedAt: identical(startedAt, _unset)
        ? this.startedAt
        : startedAt as DateTime?,
    finishedAt: identical(finishedAt, _unset)
        ? this.finishedAt
        : finishedAt as DateTime?,
  );

  /// The API form.
  JobStep toJobStep() => JobStep(
    ordinal: ordinal,
    kind: kind,
    state: state,
    sideEffect: sideEffect,
    attempts: attempts,
    result: result,
    message: message,
    startedAt: startedAt,
    finishedAt: finishedAt,
  );

  @override
  List<Object?> get props => [
    jobId,
    ordinal,
    kind,
    sideEffect,
    input,
    state,
    attempts,
    result,
    message,
    pgid,
    logPath,
    startedAt,
    finishedAt,
  ];
}

/// The API form of [job] with its [steps].
Job toJob(JobRecord job, List<StepRecord> steps) => Job(
  id: job.id,
  projectId: job.projectId,
  workflowVersionId: job.workflowVersionId,
  releaseId: job.releaseId,
  sha: job.sha,
  state: job.state,
  runnerId: job.runnerId,
  runId: job.runId,
  name: job.name,
  stage: job.runId == null ? null : job.stage,
  capabilities: job.capabilities,
  message: job.message,
  createdAt: job.createdAt,
  startedAt: job.startedAt,
  finishedAt: job.finishedAt,
  steps: [for (final step in steps) step.toJobStep()],
);

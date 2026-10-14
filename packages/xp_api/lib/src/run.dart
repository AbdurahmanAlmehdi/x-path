// `json_serializable` cannot parse `factory .name` constructors yet.
// ignore_for_file: unnecessary_type_name_in_constructor

import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:xp_api/src/job.dart';

part 'run.g.dart';

/// Where a run is, derived from its jobs.
@JsonEnum(valueField: 'wire')
enum RunState {
  /// No job has started.
  queued('queued'),

  /// A job runs, or the next stage waits for its turn.
  running('running'),

  /// No job runs and a gate waits for the owner to approve (D-13).
  waitingForApproval('waiting_for_approval'),

  /// Every job succeeded.
  succeeded('succeeded'),

  /// A job failed. Resuming it lets the run go on.
  failed('failed'),

  /// A job was cancelled.
  cancelled('cancelled');

  new(this.wire);

  /// The name on the wire.
  final String wire;
}

/// How to bump the version of the app for a run.
@JsonEnum(valueField: 'wire')
enum VersionBump {
  /// `x+1.0.0`.
  major('major'),

  /// `x.y+1.0`.
  minor('minor'),

  /// `x.y.z+1`.
  patch('patch'),

  /// Keep the version the app has.
  keep('keep');

  new(this.wire);

  /// The name on the wire.
  final String wire;
}

/// The body of `POST /projects/{id}/workflows/{workflowId}/dispatch`.
@JsonSerializable(includeIfNull: false, checked: true)
class DispatchRequest extends Equatable {
  /// Creates a request.
  const new({
    this.ref,
    this.app,
    this.flavors,
    this.platforms,
    this.bump,
    this.version,
    this.releaseVersion,
    this.release,
    this.inputs = const {},
  });

  /// Reads a request from its JSON form.
  factory DispatchRequest.fromJson(Map<String, dynamic> json) =>
      _$DispatchRequestFromJson(json);

  /// The branch, tag or commit to run on. The default is the base branch of
  /// the project.
  final String? ref;

  /// The app, by its path (`.` for the root). Needed when the project has
  /// more than one.
  final String? app;

  /// The flavors to run for. A workflow that locks the project (a release)
  /// takes the production flavors by default, any other the rest.
  final List<String>? flavors;

  /// `android` and `ios`. The default is what the app has.
  final List<String>? platforms;

  /// How to bump the version of the app.
  final VersionBump? bump;

  /// The version `x.y.z` to release, instead of [bump].
  final String? version;

  /// The release a patch applies to, `x.y.z+build`.
  final String? releaseVersion;

  /// The release (`rel_...`) this run belongs to: a new build of the same
  /// version after a rejection, or the merge of its pull request. The engine
  /// sets it for `POST /releases/{id}/builds` and `.../merge`; a workflow
  /// reads it as `release`.
  final String? release;

  /// The values of the inputs the workflow declares.
  final Map<String, dynamic> inputs;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$DispatchRequestToJson(this);

  @override
  List<Object?> get props => [
    ref,
    app,
    flavors,
    platforms,
    bump,
    version,
    releaseVersion,
    release,
    inputs,
  ];
}

/// One job of a [Run].
@JsonSerializable(includeIfNull: false)
class RunJob extends Equatable {
  /// Creates the description.
  const new({
    required this.id,
    required this.name,
    required this.stage,
    required this.state,
    this.capabilities = const [],
    this.message,
  });

  /// Reads a job description from its JSON form.
  factory RunJob.fromJson(Map<String, dynamic> json) => _$RunJobFromJson(json);

  /// The job; `GET /jobs/{id}` has its steps.
  final String id;

  /// What the workflow calls it.
  final String name;

  /// Its stage, from 0.
  final int stage;

  /// Where it is.
  final JobState state;

  /// What a runner needs to run it.
  final List<String> capabilities;

  /// Why it waits or failed.
  final String? message;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$RunJobToJson(this);

  @override
  List<Object?> get props => [id, name, stage, state, capabilities, message];
}

/// One dispatch of a workflow: the jobs it made and where they are.
@JsonSerializable(explicitToJson: true, includeIfNull: false)
class Run extends Equatable {
  /// Creates a run.
  const new({
    required this.id,
    required this.projectId,
    required this.workflowId,
    required this.workflowVersionId,
    required this.sha,
    required this.state,
    required this.locksProject,
    required this.createdAt,
    required this.jobs,
    this.ref,
    this.version,
    this.build,
  });

  /// Reads a run from its JSON form.
  factory Run.fromJson(Map<String, dynamic> json) => _$RunFromJson(json);

  /// The engine's id, for example `run_1a2b3c4d5e6f7a8b`.
  final String id;

  /// The project it runs for.
  final String projectId;

  /// The workflow it dispatched.
  final String workflowId;

  /// The exact version of the workflow it runs.
  final String workflowVersionId;

  /// The commit every job starts from, in full.
  final String sha;

  /// The ref that was asked for, when it was not a commit.
  final String? ref;

  /// Where it is.
  final RunState state;

  /// Whether the run holds the project: one such run at a time (D-11).
  final bool locksProject;

  /// The version being released, `x.y.z`, when the workflow bumps one.
  final String? version;

  /// The build number allocated at dispatch (D-11), when the workflow
  /// builds.
  final int? build;

  /// When it was dispatched, in UTC.
  final DateTime createdAt;

  /// Its jobs, by stage.
  final List<RunJob> jobs;

  /// The JSON form.
  Map<String, dynamic> toJson() => _$RunToJson(this);

  @override
  List<Object?> get props => [
    id,
    projectId,
    workflowId,
    workflowVersionId,
    sha,
    ref,
    state,
    locksProject,
    version,
    build,
    createdAt,
    jobs,
  ];
}

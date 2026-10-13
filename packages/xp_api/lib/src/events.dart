import 'package:equatable/equatable.dart';
import 'package:xp_api/src/credential.dart';
import 'package:xp_api/src/job.dart';

/// WebSocket close code of an `/events` stream whose cursor can no longer be
/// resumed. The HTTP counterpart is `409 resync_required`.
const eventStreamResyncCloseCode = 4409;

/// Something that happened in the engine, as streamed over `/events`.
///
/// Concrete events are added phase by phase. A client that meets a type it
/// does not know gets an [UnknownEvent], so an older client keeps working
/// against a newer engine.
sealed class EngineEvent extends Equatable {
  const new();

  /// Reads the event of [type] from its [payload].
  factory fromJson(String type, Map<String, dynamic> payload) => switch (type) {
    EngineStarted.eventType => EngineStarted(
      version: payload['version'] as String,
      apiVersion: payload['apiVersion'] as String,
    ),
    StreamOpened.eventType => const StreamOpened(),
    ProjectAdded.eventType => ProjectAdded(
      projectId: payload['projectId'] as String,
      fullName: payload['fullName'] as String,
    ),
    ProjectScanned.eventType => ProjectScanned(
      projectId: payload['projectId'] as String,
      errors: payload['errors'] as int,
      warnings: payload['warnings'] as int,
    ),
    ProjectRemoved.eventType => ProjectRemoved(
      projectId: payload['projectId'] as String,
    ),
    JobStateChanged.eventType => JobStateChanged(
      jobId: payload['jobId'] as String,
      projectId: payload['projectId'] as String,
      state: JobState.values.firstWhere((s) => s.wire == payload['state']),
    ),
    JobStepChanged.eventType => JobStepChanged(
      jobId: payload['jobId'] as String,
      ordinal: payload['ordinal'] as int,
      kind: payload['kind'] as String,
      state: StepState.values.byName(payload['state'] as String),
    ),
    TestRunCompleted.eventType => TestRunCompleted(
      jobId: payload['jobId'] as String,
      projectId: payload['projectId'] as String,
      branch: payload['branch'] as String,
      baseline: payload['baseline'] as bool,
      failures: payload['failures'] as int,
      newFailures: payload['newFailures'] as int,
    ),
    CredentialSaved.eventType => CredentialSaved(
      credentialId: payload['credentialId'] as String,
      projectId: payload['projectId'] as String,
      kind: CredentialKind.fromWire(payload['kind'] as String)!,
      replaced: payload['replaced'] as bool,
    ),
    CredentialVerified.eventType => CredentialVerified(
      credentialId: payload['credentialId'] as String,
      projectId: payload['projectId'] as String,
      kind: CredentialKind.fromWire(payload['kind'] as String)!,
      status: CredentialStatus.values.firstWhere(
        (status) => status.wire == payload['status'],
      ),
    ),
    CredentialExpired.eventType => CredentialExpired(
      credentialId: payload['credentialId'] as String,
      projectId: payload['projectId'] as String,
      kind: CredentialKind.fromWire(payload['kind'] as String)!,
      message: payload['message'] as String,
    ),
    CredentialRemoved.eventType => CredentialRemoved(
      credentialId: payload['credentialId'] as String,
      projectId: payload['projectId'] as String,
      kind: CredentialKind.fromWire(payload['kind'] as String)!,
    ),
    _ => UnknownEvent(type: type, payload: payload),
  };

  /// The wire name, for example `engine.started`.
  String get type;

  /// The event-specific JSON object.
  Map<String, dynamic> get payload;
}

/// The engine finished starting.
final class EngineStarted extends EngineEvent {
  /// Creates the event.
  const new({required this.version, required this.apiVersion});

  /// The wire name of this event.
  static const eventType = 'engine.started';

  /// The engine's version.
  final String version;

  /// The major version of the API the engine serves.
  final String apiVersion;

  @override
  String get type => eventType;

  @override
  Map<String, dynamic> get payload => {
    'version': version,
    'apiVersion': apiVersion,
  };

  @override
  List<Object?> get props => [version, apiVersion];
}

/// The first frame of every `/events` stream.
///
/// It is not a log entry: its `seq` is the head of the log when the stream
/// opened. A client with no cursor yet stores it as its cursor.
final class StreamOpened extends EngineEvent {
  /// Creates the event.
  const new();

  /// The wire name of this event.
  static const eventType = 'stream.opened';

  @override
  String get type => eventType;

  @override
  Map<String, dynamic> get payload => const {};

  @override
  List<Object?> get props => const [];
}

/// A project was added.
final class ProjectAdded extends EngineEvent {
  /// Creates the event.
  const new({required this.projectId, required this.fullName});

  /// The wire name of this event.
  static const eventType = 'project.added';

  /// The project's id.
  final String projectId;

  /// The repository, `owner/name`.
  final String fullName;

  @override
  String get type => eventType;

  @override
  Map<String, dynamic> get payload => {
    'projectId': projectId,
    'fullName': fullName,
  };

  @override
  List<Object?> get props => [projectId, fullName];
}

/// A project was scanned, on being added or on request.
final class ProjectScanned extends EngineEvent {
  /// Creates the event.
  const new({
    required this.projectId,
    required this.errors,
    required this.warnings,
  });

  /// The wire name of this event.
  static const eventType = 'project.scanned';

  /// The project's id.
  final String projectId;

  /// How many findings of severity `error` the scan reported.
  final int errors;

  /// How many findings of severity `warning` the scan reported.
  final int warnings;

  @override
  String get type => eventType;

  @override
  Map<String, dynamic> get payload => {
    'projectId': projectId,
    'errors': errors,
    'warnings': warnings,
  };

  @override
  List<Object?> get props => [projectId, errors, warnings];
}

/// A project was removed.
final class ProjectRemoved extends EngineEvent {
  /// Creates the event.
  const new({required this.projectId});

  /// The wire name of this event.
  static const eventType = 'project.removed';

  /// The project's id.
  final String projectId;

  @override
  String get type => eventType;

  @override
  Map<String, dynamic> get payload => {'projectId': projectId};

  @override
  List<Object?> get props => [projectId];
}

/// A job was created, started, ended, or moved to another state.
final class JobStateChanged extends EngineEvent {
  /// Creates the event.
  const new({
    required this.jobId,
    required this.projectId,
    required this.state,
  });

  /// The wire name of this event.
  static const eventType = 'job.state_changed';

  /// The job.
  final String jobId;

  /// The project the job runs for.
  final String projectId;

  /// The state the job is in now.
  final JobState state;

  @override
  String get type => eventType;

  @override
  Map<String, dynamic> get payload => {
    'jobId': jobId,
    'projectId': projectId,
    'state': state.wire,
  };

  @override
  List<Object?> get props => [jobId, projectId, state];
}

/// A step of a job moved to another state.
final class JobStepChanged extends EngineEvent {
  /// Creates the event.
  const new({
    required this.jobId,
    required this.ordinal,
    required this.kind,
    required this.state,
  });

  /// The wire name of this event.
  static const eventType = 'job.step_changed';

  /// The job.
  final String jobId;

  /// The step's position in the job, from 0.
  final int ordinal;

  /// The step type.
  final String kind;

  /// The state the step is in now.
  final StepState state;

  @override
  String get type => eventType;

  @override
  Map<String, dynamic> get payload => {
    'jobId': jobId,
    'ordinal': ordinal,
    'kind': kind,
    'state': state.name,
  };

  @override
  List<Object?> get props => [jobId, ordinal, kind, state];
}

/// A job's `test` step finished a run of the tests.
final class TestRunCompleted extends EngineEvent {
  /// Creates the event.
  const new({
    required this.jobId,
    required this.projectId,
    required this.branch,
    required this.baseline,
    required this.failures,
    required this.newFailures,
  });

  /// The wire name of this event.
  static const eventType = 'test_run.completed';

  /// The job that ran the tests.
  final String jobId;

  /// The project the job runs for.
  final String projectId;

  /// The branch that was tested.
  final String branch;

  /// Whether the run became the baseline of its app and branch.
  final bool baseline;

  /// How many tests failed or threw.
  final int failures;

  /// How many of them are new against the baseline.
  final int newFailures;

  @override
  String get type => eventType;

  @override
  Map<String, dynamic> get payload => {
    'jobId': jobId,
    'projectId': projectId,
    'branch': branch,
    'baseline': baseline,
    'failures': failures,
    'newFailures': newFailures,
  };

  @override
  List<Object?> get props => [
    jobId,
    projectId,
    branch,
    baseline,
    failures,
    newFailures,
  ];
}

/// A credential was saved: verified and stored, new or replacing an earlier
/// one.
final class CredentialSaved extends EngineEvent {
  /// Creates the event.
  const new({
    required this.credentialId,
    required this.projectId,
    required this.kind,
    required this.replaced,
  });

  /// The wire name of this event.
  static const eventType = 'credential.saved';

  /// The credential.
  final String credentialId;

  /// The project of its flavor.
  final String projectId;

  /// What it is for.
  final CredentialKind kind;

  /// Whether it replaced a credential of the same flavor and kind.
  final bool replaced;

  @override
  String get type => eventType;

  @override
  Map<String, dynamic> get payload => {
    'credentialId': credentialId,
    'projectId': projectId,
    'kind': kind.wire,
    'replaced': replaced,
  };

  @override
  List<Object?> get props => [credentialId, projectId, kind, replaced];
}

/// A credential was checked again, on request or by the daily health check.
final class CredentialVerified extends EngineEvent {
  /// Creates the event.
  const new({
    required this.credentialId,
    required this.projectId,
    required this.kind,
    required this.status,
  });

  /// The wire name of this event.
  static const eventType = 'credential.verified';

  /// The credential.
  final String credentialId;

  /// The project of its flavor.
  final String projectId;

  /// What it is for.
  final CredentialKind kind;

  /// What the check found.
  final CredentialStatus status;

  @override
  String get type => eventType;

  @override
  Map<String, dynamic> get payload => {
    'credentialId': credentialId,
    'projectId': projectId,
    'kind': kind.wire,
    'status': status.wire,
  };

  @override
  List<Object?> get props => [credentialId, projectId, kind, status];
}

/// A credential that was accepted before is refused now: it expired or was
/// revoked. Jobs that need it fail preflight until it is replaced.
final class CredentialExpired extends EngineEvent {
  /// Creates the event.
  const new({
    required this.credentialId,
    required this.projectId,
    required this.kind,
    required this.message,
  });

  /// The wire name of this event.
  static const eventType = 'credential.expired';

  /// The credential.
  final String credentialId;

  /// The project of its flavor.
  final String projectId;

  /// What it is for.
  final CredentialKind kind;

  /// What the store or tool said, with what to do about it.
  final String message;

  @override
  String get type => eventType;

  @override
  Map<String, dynamic> get payload => {
    'credentialId': credentialId,
    'projectId': projectId,
    'kind': kind.wire,
    'message': message,
  };

  @override
  List<Object?> get props => [credentialId, projectId, kind, message];
}

/// A credential was deleted, with its secret.
final class CredentialRemoved extends EngineEvent {
  /// Creates the event.
  const new({
    required this.credentialId,
    required this.projectId,
    required this.kind,
  });

  /// The wire name of this event.
  static const eventType = 'credential.removed';

  /// The credential.
  final String credentialId;

  /// The project of its flavor.
  final String projectId;

  /// What it was for.
  final CredentialKind kind;

  @override
  String get type => eventType;

  @override
  Map<String, dynamic> get payload => {
    'credentialId': credentialId,
    'projectId': projectId,
    'kind': kind.wire,
  };

  @override
  List<Object?> get props => [credentialId, projectId, kind];
}

/// An event whose type this client does not know.
final class UnknownEvent extends EngineEvent {
  /// Creates the event.
  const new({required this.type, required this.payload});

  @override
  final String type;

  @override
  final Map<String, dynamic> payload;

  @override
  List<Object?> get props => [type, payload];
}

/// An [EngineEvent] with its place in the event log.
///
/// The wire form is `{"seq": 7, "at": "...", "type": "...", "payload": {}}`.
/// `seq` grows by one per logged event, so a client that saw `seq` 7 resumes
/// with `?after=7`.
class SequencedEvent extends Equatable {
  /// Creates a sequenced event.
  const new({required this.seq, required this.at, required this.event});

  /// Reads a sequenced event from its JSON form.
  factory fromJson(Map<String, dynamic> json) => SequencedEvent(
    seq: json['seq'] as int,
    at: DateTime.parse(json['at'] as String),
    event: EngineEvent.fromJson(
      json['type'] as String,
      json['payload'] as Map<String, dynamic>,
    ),
  );

  /// Position in the event log, starting at 1.
  final int seq;

  /// When the event happened, in UTC.
  final DateTime at;

  /// What happened.
  final EngineEvent event;

  /// The JSON form.
  Map<String, dynamic> toJson() => {
    'seq': seq,
    'at': at.toUtc().toIso8601String(),
    'type': event.type,
    'payload': event.payload,
  };

  @override
  List<Object?> get props => [seq, at, event];
}

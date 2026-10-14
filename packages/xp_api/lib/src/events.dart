import 'package:equatable/equatable.dart';
import 'package:xp_api/src/approval.dart';
import 'package:xp_api/src/credential.dart';
import 'package:xp_api/src/device_token_kind.dart';
import 'package:xp_api/src/job.dart';
import 'package:xp_api/src/notification.dart';
import 'package:xp_api/src/release.dart';

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
    WorkflowSaved.eventType => WorkflowSaved(
      workflowId: payload['workflowId'] as String,
      projectId: payload['projectId'] as String,
      name: payload['name'] as String,
      version: payload['version'] as int,
    ),
    WorkflowRemoved.eventType => WorkflowRemoved(
      workflowId: payload['workflowId'] as String,
      projectId: payload['projectId'] as String,
      name: payload['name'] as String,
    ),
    RunDispatched.eventType => RunDispatched(
      runId: payload['runId'] as String,
      projectId: payload['projectId'] as String,
      workflowId: payload['workflowId'] as String,
      jobIds: (payload['jobIds'] as List<dynamic>).cast<String>(),
    ),
    ApprovalRequested.eventType => ApprovalRequested(
      approvalId: payload['approvalId'] as String,
      projectId: payload['projectId'] as String,
      action: payload['action'] as String,
      sha: payload['sha'] as String,
      version: payload['version'] as String?,
      expiresAt: DateTime.parse(payload['expiresAt'] as String),
    ),
    ApprovalDecided.eventType => ApprovalDecided(
      approvalId: payload['approvalId'] as String,
      projectId: payload['projectId'] as String,
      action: payload['action'] as String,
      state: ApprovalState.values.firstWhere(
        (state) => state.wire == payload['state'],
      ),
      decidedBy: DecidedBy.fromJson(
        payload['decidedBy'] as Map<String, dynamic>,
      ),
    ),
    ApprovalExpired.eventType => ApprovalExpired(
      approvalId: payload['approvalId'] as String,
      projectId: payload['projectId'] as String,
      action: payload['action'] as String,
    ),
    ProjectGatesChanged.eventType => ProjectGatesChanged(
      projectId: payload['projectId'] as String,
      gates: (payload['gates'] as Map<String, dynamic>).cast<String, bool>(),
      changedBy: DeviceTokenKind.values.byName(payload['changedBy'] as String),
    ),
    ReleaseCreated.eventType => ReleaseCreated(
      releaseId: payload['releaseId'] as String,
      projectId: payload['projectId'] as String,
      flavor: payload['flavor'] as String,
      version: payload['version'] as String,
      build: payload['build'] as int,
    ),
    ReleaseStateChanged.eventType => ReleaseStateChanged(
      releaseId: payload['releaseId'] as String,
      projectId: payload['projectId'] as String,
      from: ReleaseState.values.firstWhere((s) => s.wire == payload['from']),
      to: ReleaseState.values.firstWhere((s) => s.wire == payload['to']),
    ),
    ReleaseStoreChanged.eventType => ReleaseStoreChanged(
      releaseId: payload['releaseId'] as String,
      projectId: payload['projectId'] as String,
      store: ReleaseStore.values.firstWhere((s) => s.wire == payload['store']),
      state: StoreState.values.firstWhere((s) => s.wire == payload['state']),
      source: StatusSource.values.firstWhere(
        (s) => s.wire == payload['source'],
      ),
    ),
    NotificationRaised.eventType => _notification(payload),
    RunnerPaired.eventType => RunnerPaired(
      runnerId: payload['runnerId'] as String,
      name: payload['name'] as String,
    ),
    RunnerConnected.eventType => RunnerConnected(
      runnerId: payload['runnerId'] as String,
      name: payload['name'] as String,
      capabilities: (payload['capabilities'] as List<dynamic>).cast<String>(),
      slots: payload['slots'] as int,
    ),
    RunnerDisconnected.eventType => RunnerDisconnected(
      runnerId: payload['runnerId'] as String,
      name: payload['name'] as String,
    ),
    RunnerRevoked.eventType => RunnerRevoked(
      runnerId: payload['runnerId'] as String,
      name: payload['name'] as String,
    ),
    RunnerCapabilitiesChanged.eventType => RunnerCapabilitiesChanged(
      runnerId: payload['runnerId'] as String,
      name: payload['name'] as String,
      from: (payload['from'] as List<dynamic>).cast<String>(),
      to: (payload['to'] as List<dynamic>).cast<String>(),
    ),
    RunnerLeaseLost.eventType => RunnerLeaseLost(
      runnerId: payload['runnerId'] as String,
      jobId: payload['jobId'] as String,
      projectId: payload['projectId'] as String,
      reason: payload['reason'] as String,
      state: JobState.values.firstWhere((s) => s.wire == payload['state']),
    ),
    RunnerSecretDelivered.eventType => RunnerSecretDelivered(
      runnerId: payload['runnerId'] as String,
      jobId: payload['jobId'] as String,
      key: payload['key'] as String,
    ),
    _ => UnknownEvent(type: type, payload: payload),
  };

  static EngineEvent _notification(Map<String, dynamic> payload) {
    final kind = NotificationKind.fromWire(payload['kind'] as String);
    final level = NotificationLevel.fromWire(payload['level'] as String);
    // A kind or level of a newer engine: the client ignores the event.
    if (kind == null || level == null) {
      return UnknownEvent(type: NotificationRaised.eventType, payload: payload);
    }
    return NotificationRaised(
      kind: kind,
      level: level,
      title: payload['title'] as String,
      body: payload['body'] as String,
      projectId: payload['projectId'] as String?,
      releaseId: payload['releaseId'] as String?,
      jobId: payload['jobId'] as String?,
      approvalId: payload['approvalId'] as String?,
    );
  }

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

/// A workflow was created, or got a new version.
final class WorkflowSaved extends EngineEvent {
  /// Creates the event.
  const new({
    required this.workflowId,
    required this.projectId,
    required this.name,
    required this.version,
  });

  /// The wire name of this event.
  static const eventType = 'workflow.saved';

  /// The workflow.
  final String workflowId;

  /// The project it belongs to.
  final String projectId;

  /// Its name.
  final String name;

  /// The number of the version that was saved.
  final int version;

  @override
  String get type => eventType;

  @override
  Map<String, dynamic> get payload => {
    'workflowId': workflowId,
    'projectId': projectId,
    'name': name,
    'version': version,
  };

  @override
  List<Object?> get props => [workflowId, projectId, name, version];
}

/// A workflow was deleted.
final class WorkflowRemoved extends EngineEvent {
  /// Creates the event.
  const new({
    required this.workflowId,
    required this.projectId,
    required this.name,
  });

  /// The wire name of this event.
  static const eventType = 'workflow.removed';

  /// The workflow.
  final String workflowId;

  /// The project it belonged to.
  final String projectId;

  /// Its name.
  final String name;

  @override
  String get type => eventType;

  @override
  Map<String, dynamic> get payload => {
    'workflowId': workflowId,
    'projectId': projectId,
    'name': name,
  };

  @override
  List<Object?> get props => [workflowId, projectId, name];
}

/// A workflow was dispatched: its jobs exist and wait for the scheduler.
final class RunDispatched extends EngineEvent {
  /// Creates the event.
  const new({
    required this.runId,
    required this.projectId,
    required this.workflowId,
    required this.jobIds,
  });

  /// The wire name of this event.
  static const eventType = 'run.dispatched';

  /// The run.
  final String runId;

  /// The project it runs for.
  final String projectId;

  /// The workflow that was dispatched.
  final String workflowId;

  /// The jobs it made, by stage.
  final List<String> jobIds;

  @override
  String get type => eventType;

  @override
  Map<String, dynamic> get payload => {
    'runId': runId,
    'projectId': projectId,
    'workflowId': workflowId,
    'jobIds': jobIds,
  };

  @override
  List<Object?> get props => [runId, projectId, workflowId, jobIds];
}

/// An action reached a gate and asks for the owner's approval (D-13).
final class ApprovalRequested extends EngineEvent {
  /// Creates the event.
  const new({
    required this.approvalId,
    required this.projectId,
    required this.action,
    required this.sha,
    required this.expiresAt,
    this.version,
  });

  /// The wire name of this event.
  static const eventType = 'approval.requested';

  /// The approval.
  final String approvalId;

  /// The project the action happens in.
  final String projectId;

  /// What is to be approved, for example `prod_release`.
  final String action;

  /// The commit it happens on.
  final String sha;

  /// The version it releases, `x.y.z+build`, when it releases one.
  final String? version;

  /// When it counts as denied if nobody decides, in UTC.
  final DateTime expiresAt;

  @override
  String get type => eventType;

  @override
  Map<String, dynamic> get payload => {
    'approvalId': approvalId,
    'projectId': projectId,
    'action': action,
    'sha': sha,
    'version': ?version,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
  };

  @override
  List<Object?> get props => [
    approvalId,
    projectId,
    action,
    sha,
    version,
    expiresAt,
  ];
}

/// The owner approved or denied an approval. The first decision wins; there
/// is no second one (D-13).
final class ApprovalDecided extends EngineEvent {
  /// Creates the event.
  const new({
    required this.approvalId,
    required this.projectId,
    required this.action,
    required this.state,
    required this.decidedBy,
  });

  /// The wire name of this event.
  static const eventType = 'approval.decided';

  /// The approval.
  final String approvalId;

  /// The project the action happens in.
  final String projectId;

  /// What was decided about, for example `prod_release`.
  final String action;

  /// `approved` or `denied`.
  final ApprovalState state;

  /// The device that decided.
  final DecidedBy decidedBy;

  @override
  String get type => eventType;

  @override
  Map<String, dynamic> get payload => {
    'approvalId': approvalId,
    'projectId': projectId,
    'action': action,
    'state': state.wire,
    'decidedBy': decidedBy.toJson(),
  };

  @override
  List<Object?> get props => [approvalId, projectId, action, state, decidedBy];
}

/// Nobody decided an approval within 24 hours. Expired counts as denied
/// (D-13).
final class ApprovalExpired extends EngineEvent {
  /// Creates the event.
  const new({
    required this.approvalId,
    required this.projectId,
    required this.action,
  });

  /// The wire name of this event.
  static const eventType = 'approval.expired';

  /// The approval.
  final String approvalId;

  /// The project the action would have happened in.
  final String projectId;

  /// What was asked for, for example `prod_release`.
  final String action;

  @override
  String get type => eventType;

  @override
  Map<String, dynamic> get payload => {
    'approvalId': approvalId,
    'projectId': projectId,
    'action': action,
  };

  @override
  List<Object?> get props => [approvalId, projectId, action];
}

/// The gates of a project were changed: which actions wait for approval.
final class ProjectGatesChanged extends EngineEvent {
  /// Creates the event.
  const new({
    required this.projectId,
    required this.gates,
    required this.changedBy,
  });

  /// The wire name of this event.
  static const eventType = 'project.gates_changed';

  /// The project.
  final String projectId;

  /// Whether each action is gated now, for every action.
  final Map<String, bool> gates;

  /// The kind of token that changed them.
  final DeviceTokenKind changedBy;

  @override
  String get type => eventType;

  @override
  Map<String, dynamic> get payload => {
    'projectId': projectId,
    'gates': gates,
    'changedBy': changedBy.name,
  };

  @override
  List<Object?> get props => [projectId, gates, changedBy];
}

/// A release was dispatched: a new release of a flavor, in state `draft`.
final class ReleaseCreated extends EngineEvent {
  /// Creates the event.
  const new({
    required this.releaseId,
    required this.projectId,
    required this.flavor,
    required this.version,
    required this.build,
  });

  /// The wire name of this event.
  static const eventType = 'release.created';

  /// The release.
  final String releaseId;

  /// The project.
  final String projectId;

  /// The flavor.
  final String flavor;

  /// The marketing version, `x.y.z`.
  final String version;

  /// The build number.
  final int build;

  @override
  String get type => eventType;

  @override
  Map<String, dynamic> get payload => {
    'releaseId': releaseId,
    'projectId': projectId,
    'flavor': flavor,
    'version': version,
    'build': build,
  };

  @override
  List<Object?> get props => [releaseId, projectId, flavor, version, build];
}

/// A release moved to another state (D-17).
final class ReleaseStateChanged extends EngineEvent {
  /// Creates the event.
  const new({
    required this.releaseId,
    required this.projectId,
    required this.from,
    required this.to,
  });

  /// The wire name of this event.
  static const eventType = 'release.state_changed';

  /// The release.
  final String releaseId;

  /// The project.
  final String projectId;

  /// The state it was in.
  final ReleaseState from;

  /// The state it is in now.
  final ReleaseState to;

  @override
  String get type => eventType;

  @override
  Map<String, dynamic> get payload => {
    'releaseId': releaseId,
    'projectId': projectId,
    'from': from.wire,
    'to': to.wire,
  };

  @override
  List<Object?> get props => [releaseId, projectId, from, to];
}

/// The status of a release in one store changed.
final class ReleaseStoreChanged extends EngineEvent {
  /// Creates the event.
  const new({
    required this.releaseId,
    required this.projectId,
    required this.store,
    required this.state,
    required this.source,
  });

  /// The wire name of this event.
  static const eventType = 'release.store_changed';

  /// The release.
  final String releaseId;

  /// The project.
  final String projectId;

  /// Which store.
  final ReleaseStore store;

  /// Where the release is in it now.
  final StoreState state;

  /// Where that came from.
  final StatusSource source;

  @override
  String get type => eventType;

  @override
  Map<String, dynamic> get payload => {
    'releaseId': releaseId,
    'projectId': projectId,
    'store': store.wire,
    'state': state.wire,
    'source': source.wire,
  };

  @override
  List<Object?> get props => [releaseId, projectId, store, state, source];
}

/// Something the owner should hear about, for the app to show as a macOS
/// notification (D-22). The engine posts the same text to the Slack webhook of
/// the project, when it has one.
///
/// The text never holds a secret.
final class NotificationRaised extends EngineEvent {
  /// Creates the event.
  const new({
    required this.kind,
    required this.level,
    required this.title,
    required this.body,
    this.projectId,
    this.releaseId,
    this.jobId,
    this.approvalId,
  });

  /// The wire name of this event.
  static const eventType = 'notification.raised';

  /// What it is about.
  final NotificationKind kind;

  /// How much it matters.
  final NotificationLevel level;

  /// One line.
  final String title;

  /// The details: plain text, a few lines at most.
  final String body;

  /// The project it is about, when it is about one.
  final String? projectId;

  /// The release it is about.
  final String? releaseId;

  /// The job it is about.
  final String? jobId;

  /// The approval it is about.
  final String? approvalId;

  @override
  String get type => eventType;

  @override
  Map<String, dynamic> get payload => {
    'kind': kind.wire,
    'level': level.wire,
    'title': title,
    'body': body,
    'projectId': ?projectId,
    'releaseId': ?releaseId,
    'jobId': ?jobId,
    'approvalId': ?approvalId,
  };

  @override
  List<Object?> get props => [
    kind,
    level,
    title,
    body,
    projectId,
    releaseId,
    jobId,
    approvalId,
  ];
}

/// A runner was paired: a pairing token was exchanged for its credential.
final class RunnerPaired extends EngineEvent {
  /// Creates the event.
  const new({required this.runnerId, required this.name});

  /// The wire name of this event.
  static const eventType = 'runner.paired';

  /// The runner.
  final String runnerId;

  /// Its name.
  final String name;

  @override
  String get type => eventType;

  @override
  Map<String, dynamic> get payload => {'runnerId': runnerId, 'name': name};

  @override
  List<Object?> get props => [runnerId, name];
}

/// A runner connected and the engine probed it: it takes jobs now.
final class RunnerConnected extends EngineEvent {
  /// Creates the event.
  const new({
    required this.runnerId,
    required this.name,
    required this.capabilities,
    required this.slots,
  });

  /// The wire name of this event.
  static const eventType = 'runner.connected';

  /// The runner.
  final String runnerId;

  /// Its name.
  final String name;

  /// What the probe found it can do.
  final List<String> capabilities;

  /// How many jobs it runs at once.
  final int slots;

  @override
  String get type => eventType;

  @override
  Map<String, dynamic> get payload => {
    'runnerId': runnerId,
    'name': name,
    'capabilities': capabilities,
    'slots': slots,
  };

  @override
  List<Object?> get props => [runnerId, name, capabilities, slots];
}

/// A runner's connection ended. The leases it held run out 90 seconds after
/// its last heartbeat unless it comes back.
final class RunnerDisconnected extends EngineEvent {
  /// Creates the event.
  const new({required this.runnerId, required this.name});

  /// The wire name of this event.
  static const eventType = 'runner.disconnected';

  /// The runner.
  final String runnerId;

  /// Its name.
  final String name;

  @override
  String get type => eventType;

  @override
  Map<String, dynamic> get payload => {'runnerId': runnerId, 'name': name};

  @override
  List<Object?> get props => [runnerId, name];
}

/// A runner was revoked. Its credential stops working and its leases end.
final class RunnerRevoked extends EngineEvent {
  /// Creates the event.
  const new({required this.runnerId, required this.name});

  /// The wire name of this event.
  static const eventType = 'runner.revoked';

  /// The runner.
  final String runnerId;

  /// Its name.
  final String name;

  @override
  String get type => eventType;

  @override
  Map<String, dynamic> get payload => {'runnerId': runnerId, 'name': name};

  @override
  List<Object?> get props => [runnerId, name];
}

/// The probe found a runner can do something else than it could (D-19).
final class RunnerCapabilitiesChanged extends EngineEvent {
  /// Creates the event.
  const new({
    required this.runnerId,
    required this.name,
    required this.from,
    required this.to,
  });

  /// The wire name of this event.
  static const eventType = 'runner.capabilities_changed';

  /// The runner.
  final String runnerId;

  /// Its name.
  final String name;

  /// What it could do before.
  final List<String> from;

  /// What it can do now.
  final List<String> to;

  @override
  String get type => eventType;

  @override
  Map<String, dynamic> get payload => {
    'runnerId': runnerId,
    'name': name,
    'from': from,
    'to': to,
  };

  @override
  List<Object?> get props => [runnerId, name, from, to];
}

/// A runner lost the lease of a job (D-08): the lease ran out, or the runner
/// was revoked. The job is `queued` again, or `waiting_for_resume` when it has
/// a step with side effects.
final class RunnerLeaseLost extends EngineEvent {
  /// Creates the event.
  const new({
    required this.runnerId,
    required this.jobId,
    required this.projectId,
    required this.reason,
    required this.state,
  });

  /// The wire name of this event.
  static const eventType = 'runner.lease_lost';

  /// The runner.
  final String runnerId;

  /// The job.
  final String jobId;

  /// The project of the job.
  final String projectId;

  /// Why: `lapsed`, `revoked` or `offer_failed`.
  final String reason;

  /// The state the job is in now.
  final JobState state;

  @override
  String get type => eventType;

  @override
  Map<String, dynamic> get payload => {
    'runnerId': runnerId,
    'jobId': jobId,
    'projectId': projectId,
    'reason': reason,
    'state': state.wire,
  };

  @override
  List<Object?> get props => [runnerId, jobId, projectId, reason, state];
}

/// The engine gave a runner a secret of a leased job (D-09). The value is
/// never in an event.
final class RunnerSecretDelivered extends EngineEvent {
  /// Creates the event.
  const new({required this.runnerId, required this.jobId, required this.key});

  /// The wire name of this event.
  static const eventType = 'runner.secret_delivered';

  /// The runner.
  final String runnerId;

  /// The job.
  final String jobId;

  /// The key of the secret.
  final String key;

  @override
  String get type => eventType;

  @override
  Map<String, dynamic> get payload => {
    'runnerId': runnerId,
    'jobId': jobId,
    'key': key,
  };

  @override
  List<Object?> get props => [runnerId, jobId, key];
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

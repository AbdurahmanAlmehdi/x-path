import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/jobs/job_record.dart';

/// What the engine stores about a run: one dispatch of a workflow.
class RunRecord extends Equatable {
  /// Creates a record.
  const new({
    required this.id,
    required this.projectId,
    required this.workflowId,
    required this.workflowVersionId,
    required this.sha,
    required this.locksProject,
    required this.createdAt,
    this.lockHeld = false,
    this.ref,
    this.version,
    this.build,
    this.request = const {},
  });

  /// The engine's id.
  final String id;

  /// The project it runs for.
  final String projectId;

  /// The workflow that was dispatched.
  final String workflowId;

  /// The exact version of it: what every job of the run snapshots.
  final String workflowVersionId;

  /// The commit every job starts from.
  final String sha;

  /// The ref that was asked for.
  final String? ref;

  /// Whether the run takes the project while it is under way (D-11).
  final bool locksProject;

  /// Whether the run holds the project now: the scheduler started it while no
  /// other run of the project held it, and it has not failed, been cancelled
  /// or finished since. A run whose failed job is resumed holds nothing until
  /// the scheduler admits it again.
  final bool lockHeld;

  /// The version being released, `x.y.z`.
  final String? version;

  /// The build number allocated at dispatch.
  final int? build;

  /// The dispatch request, as it was sent.
  final Map<String, dynamic> request;

  /// When it was dispatched.
  final DateTime createdAt;

  /// This run with [lockHeld] set.
  RunRecord withLockHeld({required bool held}) => RunRecord(
    id: id,
    projectId: projectId,
    workflowId: workflowId,
    workflowVersionId: workflowVersionId,
    sha: sha,
    locksProject: locksProject,
    createdAt: createdAt,
    lockHeld: held,
    ref: ref,
    version: version,
    build: build,
    request: request,
  );

  /// The API form, with its [jobs] in the order they were made.
  Run toRun(List<JobRecord> jobs) => Run(
    request: dispatchRequest,
    id: id,
    projectId: projectId,
    workflowId: workflowId,
    workflowVersionId: workflowVersionId,
    sha: sha,
    ref: ref,
    state: deriveRunState(jobs.map((job) => job.state)),
    locksProject: locksProject,
    version: version,
    build: build,
    createdAt: createdAt,
    jobs: [
      for (final job in jobs)
        RunJob(
          id: job.id,
          name: job.name ?? job.id,
          stage: job.stage,
          state: job.state,
          capabilities: job.capabilities,
          message: job.message,
        ),
    ],
  );

  /// [request] as the API reads it; `null` for a run with none stored, or
  /// one stored in a form this engine no longer reads.
  DispatchRequest? get dispatchRequest {
    if (request.isEmpty) return null;
    try {
      return DispatchRequest.fromJson(request);
    } on Exception {
      // A CheckedFromJsonException: a field of a type this engine does not
      // read.
      return null;
    }
  }

  @override
  List<Object?> get props => [
    id,
    projectId,
    workflowId,
    workflowVersionId,
    sha,
    ref,
    locksProject,
    lockHeld,
    version,
    build,
    request,
    createdAt,
  ];
}

/// Where a run is, from the states of its jobs.
///
/// A run is under way (`running`) while a job runs, is interrupted or waits
/// for a resume, and between two stages. It `waitingForApproval` when no job
/// runs and a gate waits. A failed or cancelled job ends the run for good
/// unless it is resumed: the later stages stay queued.
RunState deriveRunState(Iterable<JobState> states) {
  final all = states.toList();
  // A run without jobs ran nothing (a dispatch that stopped half way).
  if (all.isEmpty) return RunState.cancelled;
  bool any(Set<JobState> wanted) => all.any(wanted.contains);
  if (any({
    JobState.running,
    JobState.interrupted,
    JobState.waitingForResume,
  })) {
    return RunState.running;
  }
  if (any({JobState.waitingForApproval})) return RunState.waitingForApproval;
  if (any({JobState.failed})) return RunState.failed;
  if (any({JobState.cancelled})) return RunState.cancelled;
  if (all.every((state) => state == JobState.succeeded)) {
    return RunState.succeeded;
  }
  return any({JobState.succeeded}) ? RunState.running : RunState.queued;
}

/// Where runs are kept.
///
/// `xp_adapters` has the SQLite implementation. The jobs of a run are in the
/// job repository, which knows their run.
abstract interface class RunRepository {
  /// Stores a new run.
  Future<void> create(RunRecord run);

  /// The run [id], or `null`.
  Future<RunRecord?> get(String id);

  /// Records whether the run [id] holds the project lock.
  Future<void> setLockHeld(String id, {required bool held});

  /// The runs that hold the project lock now.
  Future<List<RunRecord>> held();

  /// The runs, newest first: of [projectId] and of [workflowId] when given,
  /// dispatched before the run [before] when given, at most [limit].
  Future<List<RunRecord>> list({
    String? projectId,
    String? workflowId,
    String? before,
    int limit = 50,
  });
}

/// A [RunRepository] that forgets everything on exit.
class InMemoryRunRepository implements RunRepository {
  final _runs = <String, RunRecord>{};

  @override
  Future<void> create(RunRecord run) async {
    if (_runs.containsKey(run.id)) throw StateError('Run ${run.id} exists.');
    _runs[run.id] = run;
  }

  @override
  Future<RunRecord?> get(String id) async => _runs[id];

  @override
  Future<void> setLockHeld(String id, {required bool held}) async {
    _runs[id] = _runs[id]!.withLockHeld(held: held);
  }

  @override
  Future<List<RunRecord>> held() async => [
    for (final run in _runs.values)
      if (run.lockHeld) run,
  ];

  @override
  Future<List<RunRecord>> list({
    String? projectId,
    String? workflowId,
    String? before,
    int limit = 50,
  }) async {
    final newest = _runs.values.toList()..sort(_newestFirst);
    final from = before == null ? null : _runs[before];
    if (before != null && from == null) return const [];
    return newest
        .where(
          (run) =>
              (projectId == null || run.projectId == projectId) &&
              (workflowId == null || run.workflowId == workflowId) &&
              (from == null || _newestFirst(from, run) < 0),
        )
        .take(limit)
        .toList();
  }

  static int _newestFirst(RunRecord a, RunRecord b) {
    final time = b.createdAt.compareTo(a.createdAt);
    return time != 0 ? time : b.id.compareTo(a.id);
  }
}

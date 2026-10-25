import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_desktop/app/app_services.dart';
import 'package:xp_repositories/xp_repositories.dart';

sealed class JobViewEvent extends Equatable {
  const new();

  @override
  List<Object?> get props => [];
}

/// Starts following the run [runId], showing [jobId] first if given.
final class JobViewSubscriptionRequested extends JobViewEvent {
  const new(this.runId, {this.jobId});

  final String runId;
  final String? jobId;

  @override
  List<Object?> get props => [runId, jobId];
}

/// Shows the steps and the log of [jobId].
final class JobViewJobSelected extends JobViewEvent {
  const new(this.jobId);

  final String jobId;

  @override
  List<Object?> get props => [jobId];
}

/// Picks the step [ordinal] of the shown job, for "Resume from".
final class JobViewStepSelected extends JobViewEvent {
  const new(this.ordinal);

  final int? ordinal;

  @override
  List<Object?> get props => [ordinal];
}

/// Cancels every job of the run that has not ended.
final class JobViewCancelRequested extends JobViewEvent {
  const new();
}

/// Resumes the shown job at its first unfinished step, or at [fromStep].
final class JobViewResumeRequested extends JobViewEvent {
  const new({this.fromStep});

  final int? fromStep;

  @override
  List<Object?> get props => [fromStep];
}

/// Reads the artifacts of the shown job again.
final class JobViewArtifactsRequested extends JobViewEvent {
  const new();
}

/// Dispatches the run again: a new run of the same workflow version, commit
/// and request.
final class JobViewRunAgainRequested extends JobViewEvent {
  const new();
}

/// Runs the failed jobs of the run again, from the steps that failed.
final class JobViewRerunFailedRequested extends JobViewEvent {
  const new();
}

/// Downloads [artifact] to where the owner picks.
final class JobViewArtifactDownloadRequested extends JobViewEvent {
  const new(this.artifact);

  final Artifact artifact;

  @override
  List<Object?> get props => [artifact];
}

/// Reads the test counts of the run's jobs that ran their tests.
final class _JobViewTestsRequested extends JobViewEvent {
  const new();
}

/// Reads the workflow [run] runs, for the names of its stages.
final class _JobViewWorkflowRequested extends JobViewEvent {
  const new(this.run);

  final Run run;
}

/// What the job view is sending to the engine.
enum JobViewCommand { none, cancelling, resuming, dispatching, downloading }

class JobViewState extends Equatable {
  const new({
    this.loaded = false,
    this.runJobs,
    this.cached = false,
    this.outline,
    this.workflowName,
    this.selectedJobId,
    this.selectedStep,
    this.artifacts = const [],
    this.runners = const {},
    this.command = JobViewCommand.none,
    this.error,
    this.ranVersion,
    this.newestVersion,
    this.startedRunId,
    this.downloads = const {},
    this.tests,
  });

  /// Whether the run arrived (from the cache or the engine).
  final bool loaded;

  /// The run and its jobs.
  final RunJobs? runJobs;

  /// Whether [runJobs] came from the offline cache.
  final bool cached;

  /// The workflow the run runs, for the names of its stages.
  final WorkflowDocument? outline;

  /// What the workflow is called.
  final String? workflowName;

  /// The job whose steps and log are shown.
  final String? selectedJobId;

  /// The step picked in the step list, if any.
  final int? selectedStep;

  /// The artifacts of the shown job.
  final List<Artifact> artifacts;

  /// The name of each runner, by id.
  final Map<String, String> runners;

  final JobViewCommand command;

  /// What the engine said when the last command or load failed.
  final String? error;

  /// The number of the version of the workflow the run ran.
  final int? ranVersion;

  /// The number of the newest version of the workflow.
  final int? newestVersion;

  /// The run "Run again" started, for the view to open.
  final String? startedRunId;

  /// Where each artifact was downloaded to, by id.
  final Map<String, String> downloads;

  /// The test counts of the run's jobs that ran their tests, added up.
  final TestCounts? tests;

  /// Whether the workflow has a newer version than the one the run ran:
  /// "Run again" runs the one it ran.
  bool get workflowChanged =>
      ranVersion != null &&
      newestVersion != null &&
      ranVersion != newestVersion;

  Run? get run => runJobs?.run;

  /// The job whose steps and log are shown.
  Job? get selectedJob =>
      selectedJobId == null ? null : runJobs?.job(selectedJobId!);

  /// The name of stage [index] in the workflow, if the workflow has it.
  String? stageName(int index) {
    final stages = outline?.stages;
    if (stages == null || index >= stages.length) return null;
    final name = stages[index].name;
    return name.isEmpty ? null : name;
  }

  JobViewState copyWith({
    bool? loaded,
    RunJobs? runJobs,
    bool? cached,
    WorkflowDocument? outline,
    String? workflowName,
    String? selectedJobId,
    int? Function()? selectedStep,
    List<Artifact>? artifacts,
    Map<String, String>? runners,
    JobViewCommand? command,
    String? Function()? error,
    int? ranVersion,
    int? newestVersion,
    String? Function()? startedRunId,
    Map<String, String>? downloads,
    TestCounts? tests,
  }) => JobViewState(
    loaded: loaded ?? this.loaded,
    runJobs: runJobs ?? this.runJobs,
    cached: cached ?? this.cached,
    outline: outline ?? this.outline,
    workflowName: workflowName ?? this.workflowName,
    selectedJobId: selectedJobId ?? this.selectedJobId,
    selectedStep: selectedStep == null ? this.selectedStep : selectedStep(),
    artifacts: artifacts ?? this.artifacts,
    runners: runners ?? this.runners,
    command: command ?? this.command,
    error: error == null ? this.error : error(),
    ranVersion: ranVersion ?? this.ranVersion,
    newestVersion: newestVersion ?? this.newestVersion,
    startedRunId: startedRunId == null ? this.startedRunId : startedRunId(),
    downloads: downloads ?? this.downloads,
    tests: tests ?? this.tests,
  );

  @override
  List<Object?> get props => [
    loaded,
    runJobs,
    cached,
    outline,
    workflowName,
    selectedJobId,
    selectedStep,
    artifacts,
    runners,
    command,
    error,
    ranVersion,
    newestVersion,
    startedRunId,
    downloads,
    tests,
  ];
}

/// The job that a run shows first: the one that runs, else the one that
/// stopped it, else the one that waits, else the first.
String? defaultJobOf(List<Job> jobs) {
  for (final states in [
    {JobState.running},
    {JobState.failed},
    {JobState.interrupted, JobState.waitingForResume},
    {JobState.waitingForApproval},
    {JobState.cancelled},
  ]) {
    for (final job in jobs) {
      if (states.contains(job.state)) return job.id;
    }
  }
  return jobs.firstOrNull?.id;
}

/// One run in the job view (2A): its jobs for the pipeline graph, the steps
/// and artifacts of the job shown, cancel and resume.
class JobViewBloc extends Bloc<JobViewEvent, JobViewState> {
  new({
    required this._jobs,
    required this._workflows,
    required this._runners,
    required this._tests,
    required this._saveDownload,
  }) : super(const JobViewState()) {
    on<JobViewSubscriptionRequested>(_onSubscribe, transformer: restartable());
    on<_JobViewWorkflowRequested>(_onWorkflow);
    on<JobViewJobSelected>(_onJobSelected);
    on<JobViewStepSelected>(
      (event, emit) => emit(state.copyWith(selectedStep: () => event.ordinal)),
    );
    on<JobViewArtifactsRequested>(_onArtifacts, transformer: restartable());
    on<JobViewCancelRequested>(_onCancel, transformer: droppable());
    on<JobViewResumeRequested>(_onResume, transformer: droppable());
    on<JobViewRunAgainRequested>(_onRunAgain, transformer: droppable());
    on<JobViewRerunFailedRequested>(_onRerunFailed, transformer: droppable());
    on<JobViewArtifactDownloadRequested>(_onDownload, transformer: droppable());
    on<_JobViewTestsRequested>(_onTests, transformer: droppable());
  }

  final JobsRepository _jobs;
  final WorkflowsRepository _workflows;
  final RunnersRepository _runners;
  final TestsRepository _tests;
  final DownloadSaver _saveDownload;

  /// Whether the tests of the run were read since it ended.
  var _testsRead = false;

  Future<void> _onSubscribe(
    JobViewSubscriptionRequested event,
    Emitter<JobViewState> emit,
  ) async {
    // Read again (Retry): what failed before no longer stands.
    if (state.error != null) emit(state.copyWith(error: () => null));
    var askedWorkflow = false;
    final runners = emit.forEach<Snapshot<List<Runner>>>(
      _runners.watchRunners(),
      onData: (snapshot) => state.copyWith(
        runners: {for (final runner in snapshot.value) runner.id: runner.name},
      ),
      onError: (_, _) => state,
    );
    final run = emit.forEach<Snapshot<RunJobs>>(
      _jobs.watchRunJobs(event.runId),
      onData: (snapshot) {
        final jobs = snapshot.value.jobs;
        final selected =
            state.selectedJobId ?? event.jobId ?? defaultJobOf(jobs);
        final previous = state.selectedJob;
        final next = state.copyWith(
          loaded: true,
          runJobs: snapshot.value,
          cached: snapshot.cached,
          selectedJobId: selected,
        );
        if (!snapshot.cached && !askedWorkflow) {
          askedWorkflow = true;
          add(_JobViewWorkflowRequested(snapshot.value.run));
        }
        final job = next.selectedJob;
        if (job != null && (previous == null || previous.state != job.state)) {
          add(const JobViewArtifactsRequested());
        }
        if (snapshot.value.run.state.isFinished && !_testsRead) {
          _testsRead = true;
          add(const _JobViewTestsRequested());
        }
        return next;
      },
      onError: (error, _) =>
          state.copyWith(loaded: true, error: () => errorMessage(error)),
    );
    await Future.wait([run, runners]);
  }

  Future<void> _onWorkflow(
    _JobViewWorkflowRequested event,
    Emitter<JobViewState> emit,
  ) async {
    final Workflow workflow;
    final Workflow newest;
    try {
      newest = await _workflows.getWorkflow(
        event.run.projectId,
        event.run.workflowId,
      );
      workflow = await _workflows.workflowOf(event.run);
    } on Exception {
      // The stages keep their numbers; the connection banner tells why.
      return;
    }
    WorkflowDocument? outline;
    try {
      outline = WorkflowDocument.parse(workflow.yaml);
    } on WorkflowDocumentException {
      outline = null;
    }
    emit(
      state.copyWith(
        outline: outline,
        workflowName: workflow.name,
        ranVersion: workflow.version.version,
        newestVersion: newest.version.version,
      ),
    );
  }

  void _onJobSelected(JobViewJobSelected event, Emitter<JobViewState> emit) {
    if (event.jobId == state.selectedJobId) return;
    emit(
      state.copyWith(
        selectedJobId: event.jobId,
        selectedStep: () => null,
        artifacts: const [],
      ),
    );
    add(const JobViewArtifactsRequested());
  }

  Future<void> _onArtifacts(
    JobViewArtifactsRequested event,
    Emitter<JobViewState> emit,
  ) async {
    final jobId = state.selectedJobId;
    if (jobId == null) return;
    try {
      final artifacts = await _jobs.listArtifacts(jobId);
      if (state.selectedJobId == jobId) {
        emit(state.copyWith(artifacts: artifacts));
      }
    } on Exception {
      // The list stays as it was; the connection banner tells why.
    }
  }

  Future<void> _onCancel(
    JobViewCancelRequested event,
    Emitter<JobViewState> emit,
  ) async {
    final run = state.run;
    if (run == null) return;
    emit(state.copyWith(command: JobViewCommand.cancelling, error: () => null));
    try {
      await _jobs.cancelRun(run.id);
      emit(state.copyWith(command: JobViewCommand.none));
    } on Exception catch (error) {
      emit(
        state.copyWith(
          command: JobViewCommand.none,
          error: () => errorMessage(error),
        ),
      );
    }
  }

  Future<void> _onResume(
    JobViewResumeRequested event,
    Emitter<JobViewState> emit,
  ) async {
    final jobId = state.selectedJobId;
    if (jobId == null) return;
    emit(state.copyWith(command: JobViewCommand.resuming, error: () => null));
    try {
      await _jobs.resumeJob(jobId, fromStep: event.fromStep);
      emit(
        state.copyWith(command: JobViewCommand.none, selectedStep: () => null),
      );
    } on Exception catch (error) {
      emit(
        state.copyWith(
          command: JobViewCommand.none,
          error: () => errorMessage(error),
        ),
      );
    }
  }

  Future<void> _onRunAgain(
    JobViewRunAgainRequested event,
    Emitter<JobViewState> emit,
  ) async {
    final run = state.run;
    if (run == null) return;
    emit(
      state.copyWith(command: JobViewCommand.dispatching, error: () => null),
    );
    try {
      final again = await _jobs.runAgain(run.id);
      emit(
        state.copyWith(
          command: JobViewCommand.none,
          startedRunId: () => again.id,
        ),
      );
    } on Exception catch (error) {
      emit(
        state.copyWith(
          command: JobViewCommand.none,
          error: () => errorMessage(error),
        ),
      );
    }
  }

  Future<void> _onRerunFailed(
    JobViewRerunFailedRequested event,
    Emitter<JobViewState> emit,
  ) async {
    final run = state.run;
    if (run == null) return;
    emit(state.copyWith(command: JobViewCommand.resuming, error: () => null));
    try {
      await _jobs.rerunFailed(run.id);
      _testsRead = false;
      emit(state.copyWith(command: JobViewCommand.none));
    } on Exception catch (error) {
      emit(
        state.copyWith(
          command: JobViewCommand.none,
          error: () => errorMessage(error),
        ),
      );
    }
  }

  Future<void> _onDownload(
    JobViewArtifactDownloadRequested event,
    Emitter<JobViewState> emit,
  ) async {
    final artifact = event.artifact;
    emit(
      state.copyWith(command: JobViewCommand.downloading, error: () => null),
    );
    try {
      final download = await _jobs.downloadArtifact(artifact.id);
      final path = await _saveDownload(
        download.fileName ?? artifact.name,
        download.content,
      );
      emit(
        state.copyWith(
          command: JobViewCommand.none,
          downloads: path == null
              ? null
              : {...state.downloads, artifact.id: path},
        ),
      );
    } on Exception catch (error) {
      emit(
        state.copyWith(
          command: JobViewCommand.none,
          error: () => errorMessage(error),
        ),
      );
    }
  }

  Future<void> _onTests(
    _JobViewTestsRequested event,
    Emitter<JobViewState> emit,
  ) async {
    final jobs = state.runJobs?.jobs ?? const <Job>[];
    final counts = <TestCounts>[];
    for (final job in jobs) {
      final ran = job.steps.any(
        (step) =>
            step.kind == 'test' &&
            (step.state == StepState.succeeded ||
                step.state == StepState.failed),
      );
      if (!ran) continue;
      try {
        counts.add((await _tests.watchRun(job.id).first).value.run.counts);
      } on Exception {
        // Counted without it.
      }
    }
    if (counts.isEmpty) return;
    emit(
      state.copyWith(
        tests: counts.reduce(
          (a, b) => TestCounts(
            total: a.total + b.total,
            passed: a.passed + b.passed,
            failed: a.failed + b.failed,
            errored: a.errored + b.errored,
            skipped: a.skipped + b.skipped,
          ),
        ),
      ),
    );
  }
}

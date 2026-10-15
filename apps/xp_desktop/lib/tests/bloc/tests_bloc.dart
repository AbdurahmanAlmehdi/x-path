import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_repositories/xp_repositories.dart';

sealed class TestsEvent extends Equatable {
  const new();

  @override
  List<Object?> get props => [];
}

/// Starts following the test runs of [projectId], showing the run of
/// [jobId] if given, else the latest.
final class TestsSubscriptionRequested extends TestsEvent {
  const new(this.projectId, {this.jobId});

  final String projectId;
  final String? jobId;

  @override
  List<Object?> get props => [projectId, jobId];
}

/// Shows the run of [jobId].
final class TestsRunSelected extends TestsEvent {
  const new(this.jobId);

  final String jobId;

  @override
  List<Object?> get props => [jobId];
}

final class _TestsRunRequested extends TestsEvent {
  const new(this.jobId);

  final String jobId;
}

/// A test run the app knows of, by the job that ran it, with what is known
/// about it before it is read.
class KnownTestRun extends Equatable {
  const new({
    required this.jobId,
    this.branch,
    this.appPath,
    this.createdAt,
    this.baseline = false,
  });

  final String jobId;
  final String? branch;
  final String? appPath;
  final DateTime? createdAt;

  /// Whether it is a baseline of its app and branch.
  final bool baseline;

  @override
  List<Object?> get props => [jobId, branch, appPath, createdAt, baseline];
}

class TestsState extends Equatable {
  const new({
    this.loaded = false,
    this.baselines = const [],
    this.completed = const [],
    this.selectedJobId,
    this.run,
    this.read = const {},
    this.runCached = false,
    this.runError,
    this.job,
    this.error,
  });

  /// Whether the baselines arrived (from the cache or the engine).
  final bool loaded;

  /// The baselines of the project, one per app and branch.
  final List<TestBaseline> baselines;

  /// The runs of the project that ended while the app watched, newest first.
  final List<TestRunCompleted> completed;

  /// The run picked, if any.
  final String? selectedJobId;

  /// The run shown, with its failing tests.
  final TestRunResponse? run;

  /// Every run read so far, by job: what the run picker says about them.
  final Map<String, TestRun> read;

  /// Whether [run] came from the offline cache.
  final bool runCached;

  /// Why the shown run could not be read.
  final String? runError;

  /// The job that ran [run]: its test step's duration and its run.
  final Job? job;

  /// Why the baselines could not be read.
  final String? error;

  /// The newest baseline.
  TestBaseline? get _newestBaseline => baselines.isEmpty
      ? null
      : baselines.reduce((a, b) => b.createdAt.isAfter(a.createdAt) ? b : a);

  /// The job of the run shown: the one picked, else the latest that ended
  /// while the app watched, else the newest baseline.
  String? get shownJobId =>
      selectedJobId ?? completed.firstOrNull?.jobId ?? _newestBaseline?.jobId;

  /// The baseline [run] was compared with, if the project still has it.
  TestBaseline? get comparedBaseline {
    final jobId = run?.run.diff.comparedTo;
    return baselines.where((baseline) => baseline.jobId == jobId).firstOrNull;
  }

  /// Every run the app knows of: those that ended while it watched, the one
  /// picked, those read before, then the baselines, newest first.
  List<KnownTestRun> get runs {
    final known = <String, KnownTestRun>{};
    void add(KnownTestRun entry) => known.putIfAbsent(entry.jobId, () {
      final run = read[entry.jobId];
      return run == null
          ? entry
          : KnownTestRun(
              jobId: run.jobId,
              branch: run.branch,
              appPath: run.appPath,
              createdAt: run.createdAt,
              baseline: run.baseline,
            );
    });
    for (final event in completed) {
      add(
        KnownTestRun(
          jobId: event.jobId,
          branch: event.branch,
          baseline: event.baseline,
        ),
      );
    }
    if (selectedJobId case final jobId?) add(KnownTestRun(jobId: jobId));
    for (final jobId in read.keys) {
      add(KnownTestRun(jobId: jobId));
    }
    for (final baseline in [
      ...baselines,
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt))) {
      add(
        KnownTestRun(
          jobId: baseline.jobId,
          branch: baseline.branch,
          appPath: baseline.appPath,
          createdAt: baseline.createdAt,
          baseline: true,
        ),
      );
    }
    return [...known.values];
  }

  /// How long the job's `test` step ran, once it ended.
  Duration? get duration {
    final step = job?.steps.where((step) => step.kind == 'test').lastOrNull;
    final start = step?.startedAt;
    final end = step?.finishedAt;
    return start == null || end == null ? null : end.difference(start);
  }

  TestsState copyWith({
    bool? loaded,
    List<TestBaseline>? baselines,
    List<TestRunCompleted>? completed,
    String? Function()? selectedJobId,
    TestRunResponse? Function()? run,
    Map<String, TestRun>? read,
    bool? runCached,
    String? Function()? runError,
    Job? Function()? job,
    String? Function()? error,
  }) => TestsState(
    loaded: loaded ?? this.loaded,
    baselines: baselines ?? this.baselines,
    completed: completed ?? this.completed,
    selectedJobId: selectedJobId == null ? this.selectedJobId : selectedJobId(),
    run: run == null ? this.run : run(),
    read: read ?? this.read,
    runCached: runCached ?? this.runCached,
    runError: runError == null ? this.runError : runError(),
    job: job == null ? this.job : job(),
    error: error == null ? this.error : error(),
  );

  @override
  List<Object?> get props => [
    loaded,
    baselines,
    completed,
    selectedJobId,
    run,
    read,
    runCached,
    runError,
    job,
    error,
  ];
}

/// The tests of a project: the latest run against its baseline, new failures
/// first (D-21). The engine lists no past runs, so the runs on offer are the
/// baselines, the runs that end while the app watches and the run a job
/// view opened.
class TestsBloc extends Bloc<TestsEvent, TestsState> {
  new({required this._tests, required this._jobs}) : super(const TestsState()) {
    on<TestsSubscriptionRequested>(_onSubscribe, transformer: restartable());
    on<TestsRunSelected>(
      (event, emit) =>
          _show(emit, state.copyWith(selectedJobId: () => event.jobId)),
    );
    on<_TestsRunRequested>(_onRun, transformer: restartable());
  }

  final TestsRepository _tests;
  final JobsRepository _jobs;

  /// The job whose run is being read.
  String? _readingJobId;

  /// Emits [next], and reads its run when the run shown changed.
  void _show(Emitter<TestsState> emit, TestsState next) {
    emit(next);
    final jobId = next.shownJobId;
    if (jobId != null && jobId != _readingJobId) {
      _readingJobId = jobId;
      add(_TestsRunRequested(jobId));
    }
  }

  Future<void> _onSubscribe(
    TestsSubscriptionRequested event,
    Emitter<TestsState> emit,
  ) async {
    _show(emit, TestsState(selectedJobId: event.jobId));
    final baselines = emit.forEach<Snapshot<List<TestBaseline>>>(
      _tests.watchBaselines(event.projectId),
      onData: (snapshot) {
        _show(
          emit,
          state.copyWith(
            loaded: true,
            baselines: snapshot.value,
            error: () => null,
          ),
        );
        return state;
      },
      onError: (error, _) =>
          state.copyWith(loaded: true, error: () => errorMessage(error)),
    );
    final completed = emit.forEach<TestRunCompleted>(
      _tests.completedRuns(event.projectId),
      onData: (run) {
        _show(
          emit,
          state.copyWith(
            completed: [
              run,
              for (final other in state.completed)
                if (other.jobId != run.jobId) other,
            ],
          ),
        );
        return state;
      },
    );
    await Future.wait([baselines, completed]);
  }

  Future<void> _onRun(
    _TestsRunRequested event,
    Emitter<TestsState> emit,
  ) async {
    emit(
      state.copyWith(run: () => null, runError: () => null, job: () => null),
    );
    final run = emit.forEach<Snapshot<TestRunResponse>>(
      _tests.watchRun(event.jobId),
      onData: (snapshot) => state.copyWith(
        run: () => snapshot.value,
        read: {...state.read, event.jobId: snapshot.value.run},
        runCached: snapshot.cached,
        runError: () => null,
      ),
      onError: (error, _) =>
          state.copyWith(runError: () => errorMessage(error)),
    );
    final job = emit.forEach<Snapshot<Job>>(
      _jobs.watchJob(event.jobId),
      onData: (snapshot) => state.copyWith(job: () => snapshot.value),
      // The run says what matters; without its job only the duration and
      // the way to the job view are missing.
      onError: (_, _) => state,
    );
    await Future.wait([run, job]);
  }
}

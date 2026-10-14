import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:xp/src/runner/job/chunk_log_store.dart';
import 'package:xp/src/runner/job/lease_job_repository.dart';
import 'package:xp/src/runner/job/lease_outbox.dart';
import 'package:xp/src/runner/job/lease_paths.dart';
import 'package:xp/src/runner/job/pgid_journal.dart';
import 'package:xp/src/runner/job/remote_checkout_step.dart';
import 'package:xp/src/runner/job/uploading_artifacts.dart';
import 'package:xp/src/runner/runner_paths.dart';
import 'package:xp/src/runner/secrets/lease_secret_store.dart';
import 'package:xp/src/runner/secrets/secret_area.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

/// The job of one lease, running on this machine.
abstract interface class LeaseWork {
  /// Completes when the steps ended, the job's secrets and files are gone and
  /// its end is in the outbox (unless the job was cancelled).
  Future<void> get finished;

  /// Stops the job: its process groups end, its secrets and files are wiped,
  /// and nothing more is reported (the engine ended the lease, or the runner
  /// is going away). Completes when that is done.
  Future<void> cancel();
}

/// What the registry of steps of a lease is made from.
class LeaseServices {
  /// Creates the services.
  const new({
    required this.jobs,
    required this.secrets,
    required this.artifacts,
    required this.artifactStore,
    required this.source,
    required this.paths,
  });

  /// The job and its steps.
  final JobRepository jobs;

  /// The secrets of the job, asked of the engine.
  final SecretStore secrets;

  /// The records of the artifacts the job makes; recording uploads.
  final ArtifactRepository artifacts;

  /// Where the files of those artifacts are.
  final ArtifactStore artifactStore;

  /// Where the source of the job comes from.
  final LeaseSource source;

  /// The paths of the job on this machine.
  final LeasePaths paths;
}

/// Makes the steps a runner can run, for one lease.
typedef RegistryFactory = StepRegistry Function(LeaseServices services);

/// What every lease of a runner shares.
class JobEnvironment {
  /// Creates the environment.
  const new({
    required this.paths,
    required this.supervisor,
    required this.hostEnvironment,
    required this.secretArea,
    required this.journal,
    required this.power,
    required this.clock,
    required this.upload,
    required this.removeWorktree,
    this.random,
  });

  /// The data directory.
  final RunnerPaths paths;

  /// Starts the processes of steps, each in its own group (ADR 0003). Its
  /// masker is told every secret the engine delivers.
  final ProcessSupervisor supervisor;

  /// The environment the processes of steps are made from.
  final Map<String, String> hostEnvironment;

  /// Where the secrets of jobs are.
  final SecretArea secretArea;

  /// Remembers the process groups of running steps.
  final PgidJournal journal;

  /// Keeps the machine awake while jobs run.
  final PowerAssertion power;

  /// The time.
  final Clock clock;

  /// Uploads artifacts to the engine.
  final ArtifactUpload upload;

  /// Removes a worktree and what git knows of it.
  final Future<void> Function(GitWorktree worktree) removeWorktree;

  /// For tests.
  final Random? random;
}

/// Runs the job of a lease through the shared step runner (`JobRunner`) of
/// the engine, with the steps a runner can run, and reports to the engine as
/// it goes (D-08):
///
/// - the steps come from the offer, with the paths of the engine's disk
///   translated to this machine's ([LeasePaths]); every step starts again, as
///   the work of an earlier lease is not on this machine, but its attempts are
///   kept, so that a step with side effects asks first whether its work
///   exists ([Step.alreadyDone]);
/// - the state of each step becomes a `step_state` frame, the output of the
///   processes `log_chunk` frames, the files of builds uploads;
/// - the secrets the steps name are asked of the engine when a step reads
///   them, and are wiped when the job ends, however it ends;
/// - the end becomes `job_done`, with the explanation of a failure.
///
/// A job that is cancelled or interrupted reports nothing: the engine ended
/// the lease, or the runner is going away and the lease lapses (D-08).
class LeasedJob implements LeaseWork {
  /// Starts the job of `offer`.
  new({
    required this._offer,
    required this._outbox,
    required this._environment,
    required this._requestSecret,
    required this._registry,
  }) {
    finished = _run();
  }

  final LeaseOfferFrame _offer;
  final LeaseOutbox _outbox;
  final JobEnvironment _environment;
  final SecretRequester _requestSecret;
  final RegistryFactory _registry;
  final _serial = SerialQueues();
  final _journalWrites = <Future<void>>[];
  JobRunner? _runner;
  LeasePaths? _paths;
  var _stopped = false;
  var _cleaned = false;

  @override
  late final Future<void> finished;

  String get _jobId => _offer.jobId;

  @override
  Future<void> cancel() async {
    _stopped = true;
    try {
      await _runner?.cancel(_jobId);
    } on JobException {
      // It ended already.
    }
    await finished;
    _outbox.abandon();
  }

  Future<void> _run() async {
    try {
      await _execute();
    } on Object catch (error) {
      await _cleanUp();
      if (!_stopped) {
        final masker = _environment.supervisor.masker.newStream();
        _outbox.finish(
          state: JobState.failed,
          message:
              masker.add('The runner could not run the job: $error') +
              masker.flush(),
        );
      }
    } finally {
      await _cleanUp();
    }
  }

  Future<void> _execute() async {
    final environment = _environment;
    final clock = environment.clock;
    final inputs = [for (final step in _offer.steps) step.input];
    final paths = _paths = LeasePaths.of(
      inputs,
      sourceDirectory: environment.paths.source,
    );
    final repository = LeaseJobRepository(
      onStep: _reportStep,
      onProcessGroup: (jobId, ordinal, pgid) =>
          _journalWrites.add(environment.journal.track(jobId, ordinal, pgid)),
    );
    final artifactStore = DirectoryArtifactStore(environment.paths.jobs);
    final secrets = LeaseSecretStore(
      jobId: _jobId,
      granted: _offer.secrets,
      area: environment.secretArea,
      request: _requestSecret,
      masker: environment.supervisor.masker,
    );
    final services = LeaseServices(
      jobs: repository,
      secrets: secrets,
      artifacts: UploadingArtifactRepository(
        store: artifactStore,
        upload: environment.upload,
        leaseId: _offer.leaseId,
      ),
      artifactStore: artifactStore,
      source: LeaseSource.of(_offer),
      paths: paths,
    );
    final runner = JobRunner(
      jobs: repository,
      steps: _registry(services),
      supervisor: environment.supervisor,
      logs: JobLogs(store: ChunkLogStore(_outbox)),
      secrets: secrets,
      secretFiles: environment.secretArea.files,
      power: environment.power,
      events: InMemoryEventLog(clock: clock, capacity: 16),
      clock: clock,
      hostEnvironment: environment.hostEnvironment,
      random: environment.random,
    );
    await repository.create(
      JobRecord(
        id: _jobId,
        workflowVersionId: 'lease',
        projectId: _offer.projectId,
        state: JobState.queued,
        createdAt: clock.now(),
        sha: _offer.sha,
        stage: _offer.stage,
        name: _offer.name,
        capabilities: _offer.capabilities,
      ),
      [
        for (final step in _offer.steps)
          StepRecord(
            jobId: _jobId,
            ordinal: step.ordinal,
            kind: step.kind,
            sideEffect: step.sideEffect,
            input: paths.input(step.input),
            attempts: step.attempts,
          ),
      ],
    );
    if (_stopped) return;
    _runner = runner;
    await runner.start(_jobId);
    await runner.whenFinished(_jobId);
    final job = (await repository.get(_jobId))!;
    // The secrets go before the end is reported: nothing of the job is left
    // on this machine when the engine hears that it ended.
    await _cleanUp();
    if (_stopped) return;
    _report(job);
  }

  void _report(JobRecord job) {
    switch (job.state) {
      case JobState.succeeded:
        _outbox.finish(state: JobState.succeeded);
      case JobState.cancelled:
      case JobState.failed:
        _outbox.finish(state: job.state, message: job.message);
      case JobState.queued:
      case JobState.running:
      case JobState.interrupted:
      case JobState.waitingForResume:
      case JobState.waitingForApproval:
        _outbox.finish(
          state: JobState.failed,
          message:
              'The job stopped in state ${job.state.wire} on the runner'
              '${job.message == null ? '' : ': ${job.message}'}.',
        );
    }
  }

  void _reportStep(StepRecord step) => _outbox.step(
    StepStateFrame(
      jobId: step.jobId,
      leaseId: _offer.leaseId,
      ordinal: step.ordinal,
      state: step.state,
      attempts: step.attempts,
      result: step.result,
      message: step.message,
      startedAt: step.startedAt,
      finishedAt: step.finishedAt,
    ),
  );

  /// Wipes everything the job left on this machine: its secrets, the files of
  /// its builds, its worktree. Safe to call again.
  Future<void> _cleanUp() => _serial.run('clean', () async {
    if (_cleaned) return;
    _cleaned = true;
    final environment = _environment;
    try {
      await Future.wait(_journalWrites);
      await environment.secretArea.deleteJob(_jobId);
    } finally {
      final worktree = _paths?.worktree;
      if (worktree != null) {
        try {
          await environment.removeWorktree(worktree);
        } on Object {
          // Whatever git cannot remove, the directory below does.
        }
        final directory = Directory(worktree.path);
        if (directory.existsSync()) directory.deleteSync(recursive: true);
      }
      final work = Directory(environment.paths.jobDirectory(_jobId));
      if (work.existsSync()) work.deleteSync(recursive: true);
    }
  });
}

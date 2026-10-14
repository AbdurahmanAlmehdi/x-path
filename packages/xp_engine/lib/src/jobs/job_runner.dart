import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/clock/clock.dart';
import 'package:xp_engine/src/jobs/job_control.dart';
import 'package:xp_engine/src/jobs/job_exceptions.dart';
import 'package:xp_engine/src/jobs/job_logs.dart';
import 'package:xp_engine/src/jobs/job_record.dart';
import 'package:xp_engine/src/jobs/job_repository.dart';
import 'package:xp_engine/src/jobs/secret_file_store.dart';
import 'package:xp_engine/src/process/output_line.dart';
import 'package:xp_engine/src/process/output_masker.dart';
import 'package:xp_engine/src/process/power_assertion.dart';
import 'package:xp_engine/src/process/process_environment.dart';
import 'package:xp_engine/src/process/process_supervisor.dart';
import 'package:xp_engine/src/repositories/event_log.dart';
import 'package:xp_engine/src/secrets/secret_store.dart';
import 'package:xp_engine/src/steps/step.dart';
import 'package:xp_engine/src/steps/step_context.dart';
import 'package:xp_engine/src/steps/step_registry.dart';

final _variableName = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

/// Creates jobs and runs their steps in order (D-18).
///
/// Every step records its state, result and output as it goes. A job that is
/// run again, with [resume], continues at its first step that is not done:
/// steps that succeeded or were skipped are not run again, a step that failed
/// or was interrupted is. A step with side effects that was started before
/// first asks [Step.alreadyDone] whether its work exists, and is skipped if
/// so.
///
/// While a job runs the machine is kept awake ([PowerAssertion]), each
/// process runs in its own process group so that a cancel stops the whole
/// tree, and the output of the processes is masked, logged and streamed.
///
/// Scheduling (how many jobs run at once, which runner) is not done here:
/// [start] starts a job at once.
class JobRunner implements JobControl {
  /// Creates a runner.
  ///
  /// `hostEnvironment` is the engine's own environment, from which processes
  /// get only the allowed variables. [onError] hears about failures of the
  /// engine's own bookkeeping (a job whose database writes fail); the job is
  /// failed when it can be. [random] is for tests; it must be cryptographically
  /// secure otherwise.
  new({
    required this._jobs,
    required this._steps,
    required this._supervisor,
    required this._logs,
    required this._secrets,
    required this._secretFiles,
    required this._power,
    required this._events,
    required this._clock,
    required this._hostEnvironment,
    this.onError,
    Random? random,
  }) : _random = random ?? Random.secure();

  /// Hears about bookkeeping failures; see the constructor.
  final void Function(Object error, StackTrace stackTrace)? onError;

  final JobRepository _jobs;
  final StepRegistry _steps;
  final ProcessSupervisor _supervisor;
  final JobLogs _logs;
  final SecretStore _secrets;
  final SecretFileStore _secretFiles;
  final PowerAssertion _power;
  final EventLog _events;
  final Clock _clock;
  final Map<String, String> _hostEnvironment;
  final Random _random;
  final _active = <String, _Run>{};

  /// The ids of the jobs that are running now.
  Iterable<String> get activeJobs => _active.keys;

  /// A new job id. A caller that needs to know the ids of jobs before it
  /// creates them (a run whose jobs refer to each other) asks for them here
  /// and passes one to [create].
  String newJobId() => 'job_${_hex(8)}';

  /// Creates a queued job that runs [steps] in order.
  ///
  /// [id] is one from [newJobId]. A job that belongs to a run of a workflow
  /// says which ([runId]), in which [stage], what the workflow calls it
  /// ([name]) and what a runner needs to run it ([capabilities]).
  Future<Job> create({
    required String workflowVersionId,
    required String projectId,
    required List<StepPlan> steps,
    String? id,
    String? releaseId,
    String? sha,
    String? runId,
    int stage = 0,
    String? name,
    List<String> capabilities = const [],
  }) async {
    final job = JobRecord(
      id: id ?? newJobId(),
      workflowVersionId: workflowVersionId,
      projectId: projectId,
      releaseId: releaseId,
      sha: sha,
      runId: runId,
      stage: stage,
      name: name,
      capabilities: capabilities,
      state: JobState.queued,
      createdAt: _clock.now(),
    );
    final records = [
      for (final (ordinal, plan) in steps.indexed)
        StepRecord(
          jobId: job.id,
          ordinal: ordinal,
          kind: plan.kind,
          sideEffect: plan.sideEffect,
          input: plan.input,
        ),
    ];
    await _jobs.create(job, records);
    _announceJob(job);
    return toJob(job, records);
  }

  /// The job [id] with its steps.
  ///
  /// Throws a [JobNotFoundException] if there is none.
  @override
  Future<Job> get(String id) async =>
      toJob(await _require(id), await _jobs.steps(id));

  /// Starts the queued job [id] and returns it, running. The steps run in the
  /// background; see [whenFinished].
  ///
  /// Throws a [JobNotFoundException] if there is no such job and a
  /// [JobStateException] if it is not queued.
  Future<Job> start(String id) async {
    final job = await _require(id);
    if (job.state != JobState.queued) {
      throw JobStateException(
        'Job $id is ${job.state.wire}, not queued. Use resume to run it again.',
      );
    }
    return await _launch(job);
  }

  /// Runs the job [id] again and returns it, running.
  ///
  /// It continues at its first step that is not done. With [fromStep] it
  /// continues at that step even if it succeeded, and the steps after it run
  /// again too.
  ///
  /// Throws a [JobNotFoundException] if there is no such job, a
  /// [JobStateException] unless it is failed, cancelled, interrupted, waiting
  /// for a resume or waiting for an approval, and a [JobInvalidException] if
  /// [fromStep] is not a step of the job or a step before it is not done.
  @override
  Future<Job> resume(String id, {int? fromStep}) async {
    final job = await _prepareResume(id, fromStep);
    return await _launch(job);
  }

  /// Makes the job [id] ready to run again, as [resume] does, but leaves it
  /// `queued` for the scheduler to start. Returns it.
  ///
  /// Throws what [resume] throws.
  Future<Job> requeue(String id, {int? fromStep}) async {
    final job = await _prepareResume(id, fromStep);
    final queued = job.copyWith(
      state: JobState.queued,
      message: null,
      finishedAt: null,
    );
    await _saveJob(queued);
    return toJob(queued, await _jobs.steps(id));
  }

  Future<JobRecord> _prepareResume(String id, int? fromStep) async {
    final job = await _require(id);
    const resumable = {
      JobState.failed,
      JobState.cancelled,
      JobState.interrupted,
      JobState.waitingForResume,
      JobState.waitingForApproval,
    };
    if (_active.containsKey(id) || !resumable.contains(job.state)) {
      throw JobStateException(
        'Job $id is ${job.state.wire}, so it cannot be resumed. A job can be '
        'resumed when it is failed, cancelled, interrupted, waiting for a '
        'resume or waiting for an approval.',
      );
    }
    if (fromStep != null) await _rewind(id, fromStep);
    return job;
  }

  /// Cancels the job [id] and returns it once it has ended.
  ///
  /// A running job has its process group stopped (`SIGTERM`, then `SIGKILL`
  /// after the grace period) first. A queued, interrupted or waiting job is
  /// cancelled at once.
  ///
  /// Throws a [JobNotFoundException] if there is no such job and a
  /// [JobStateException] if it ended already.
  @override
  Future<Job> cancel(String id) async {
    final job = await _require(id);
    final run = _active[id];
    if (run != null) {
      run.cancelRequested = true;
      await run.process?.cancel();
      await run.done.future;
      return await get(id);
    }
    if (job.state.isFinished) {
      throw JobStateException('Job $id has ended (${job.state.wire}).');
    }
    for (final step in await _jobs.steps(id)) {
      if (step.state == StepState.interrupted ||
          step.state == StepState.waitingForApproval) {
        await _saveStep(step.copyWith(state: StepState.cancelled));
      }
    }
    await _saveJob(
      job.copyWith(
        state: JobState.cancelled,
        message: 'Cancelled.',
        finishedAt: _clock.now(),
      ),
    );
    return await get(id);
  }

  /// Completes when the job [id] is no longer running, with the job. Completes
  /// at once for a job that does not run.
  Future<Job> whenFinished(String id) async {
    await _active[id]?.done.future;
    return await get(id);
  }

  /// Stops every running job the way a restart would: the processes are
  /// stopped, the interrupted steps and jobs are recorded, and a job with an
  /// interrupted side-effect step waits for an explicit resume (D-18).
  Future<void> interruptAll() async {
    final runs = _active.values.toList();
    for (final run in runs) {
      run.interruptRequested = true;
    }
    await Future.wait<void>([
      for (final run in runs) (run.process?.cancel() ?? Future<void>.value()),
    ]);
    await Future.wait<void>([for (final run in runs) run.done.future]);
  }

  // ------------------------------------------------------------- execution

  Future<Job> _launch(JobRecord job) async {
    final run = _Run();
    _active[job.id] = run;
    final running = job.copyWith(
      state: JobState.running,
      message: null,
      startedAt: _clock.now(),
      finishedAt: null,
    );
    try {
      await _saveJob(running);
    } on Object {
      _active.remove(job.id);
      rethrow;
    }
    unawaited(_execute(running, run));
    return toJob(running, await _jobs.steps(job.id));
  }

  Future<void> _execute(JobRecord job, _Run run) async {
    try {
      await _power.hold();
      await _logs.begin(job.id);
      await _runSteps(job, run);
    } on Object catch (error, stackTrace) {
      onError?.call(error, stackTrace);
      await _failQuietly(job, error);
    } finally {
      await _cleanUp(job.id, run);
    }
  }

  Future<void> _cleanUp(String jobId, _Run run) async {
    try {
      await _logs.end(jobId);
      await _secretFiles.deleteAll(jobId);
      await _power.release();
    } on Object catch (error, stackTrace) {
      onError?.call(error, stackTrace);
    } finally {
      _active.remove(jobId);
      run.done.complete();
    }
  }

  Future<void> _failQuietly(JobRecord job, Object error) async {
    try {
      final latest = await _require(job.id);
      await _saveJob(
        latest.copyWith(
          state: JobState.failed,
          message: _mask('The engine failed to run the job: $error'),
          finishedAt: _clock.now(),
        ),
      );
    } on Object catch (error, stackTrace) {
      onError?.call(error, stackTrace);
    }
  }

  Future<void> _runSteps(JobRecord job, _Run run) async {
    for (final step in await _jobs.steps(job.id)) {
      if (step.state.isDone) continue;
      if (run.stopping) break;
      final ended = await _runStep(step, run);
      if (ended == StepState.failed || ended == StepState.waitingForApproval) {
        break;
      }
    }
    await _finish(job, run);
  }

  Future<void> _finish(JobRecord job, _Run run) async {
    final steps = await _jobs.steps(job.id);
    final latest = await _require(job.id);
    final failed = steps.where((s) => s.state == StepState.failed).firstOrNull;
    final waiting = steps
        .where((s) => s.state == StepState.waitingForApproval)
        .firstOrNull;
    final (state, message) = switch (run) {
      // The work was done before the stop mattered.
      _ when steps.every((s) => s.state.isDone) => (JobState.succeeded, null),
      _Run(cancelRequested: true) => (JobState.cancelled, 'Cancelled.'),
      _Run(interruptRequested: true) => (
        steps.any((s) => s.state == StepState.interrupted && s.sideEffect)
            ? JobState.waitingForResume
            : JobState.interrupted,
        'The engine stopped while the job was running.',
      ),
      _ when failed != null => (
        JobState.failed,
        'Step ${failed.ordinal} (${failed.kind}) failed: ${failed.message}',
      ),
      _ when waiting != null => (
        JobState.waitingForApproval,
        'Step ${waiting.ordinal} (${waiting.kind}) waits: ${waiting.message}',
      ),
      _ => (JobState.succeeded, null),
    };
    await _saveJob(
      latest.copyWith(state: state, message: message, finishedAt: _clock.now()),
    );
  }

  /// Runs one step and returns the state it ended in.
  Future<StepState> _runStep(StepRecord record, _Run run) async {
    final step = _steps[record.kind];
    if (step == null) {
      return await _fail(
        record,
        'The engine has no step of kind "${record.kind}".',
      );
    }
    final context = _RunnerContext(this, run, record);
    final Object? input;
    try {
      input = step.decodeInput(record.input);
    } on Object catch (error) {
      return await _fail(record, 'The step input is not valid: $error');
    }
    if (record.sideEffect && record.attempts > 0) {
      final skipped = await _alreadyDone(step, input, record, context);
      if (skipped != null) return skipped;
    }
    context.record = record.copyWith(
      state: StepState.running,
      attempts: record.attempts + 1,
      result: null,
      message: null,
      pgid: null,
      startedAt: _clock.now(),
      finishedAt: null,
    );
    await _saveStep(context.record);

    StepOutcome<Object?> outcome;
    try {
      outcome = await step.run(input, context);
    } on Object catch (error) {
      outcome = StepFailed(_mask(error.toString()));
    }
    var ended = context.record.copyWith(pgid: null, finishedAt: _clock.now());
    try {
      ended = switch (outcome) {
        StepSucceeded(:final result) => ended.copyWith(
          state: StepState.succeeded,
          result: step.encodeResult(result),
        ),
        StepSkipped(:final reason) => ended.copyWith(
          state: StepState.skipped,
          message: reason,
        ),
        StepFailed(:final message) => ended.copyWith(
          state: StepState.failed,
          message: _mask(message),
        ),
        StepWaiting(:final reason) => ended.copyWith(
          state: StepState.waitingForApproval,
          message: _mask(reason),
        ),
      };
    } on Object catch (error) {
      ended = ended.copyWith(
        state: StepState.failed,
        message: _mask('The step result cannot be stored: $error'),
      );
    }
    if (ended.state == StepState.failed) {
      if (run.cancelRequested) {
        ended = ended.copyWith(state: StepState.cancelled, message: null);
      } else if (run.interruptRequested) {
        ended = ended.copyWith(state: StepState.interrupted, message: null);
      }
    }
    await _saveStep(ended);
    return ended.state;
  }

  Future<StepState> _fail(StepRecord record, String message) async {
    await _saveStep(
      record.copyWith(
        state: StepState.failed,
        message: _mask(message),
        finishedAt: _clock.now(),
      ),
    );
    return StepState.failed;
  }

  /// Asks the step whether its work exists and, if so, records the step as
  /// skipped. Returns the state the step ended in, or `null` if it has to run.
  Future<StepState?> _alreadyDone(
    Step<Object?, Object?> step,
    Object? input,
    StepRecord record,
    StepContext context,
  ) async {
    try {
      final done = await step.alreadyDone(input, context);
      if (done == null) return null;
      await _saveStep(
        record.copyWith(
          state: StepState.skipped,
          result: step.encodeResult(done),
          message: 'Already done.',
          finishedAt: _clock.now(),
        ),
      );
      return StepState.skipped;
    } on Object catch (error) {
      return await _fail(
        record,
        'Could not tell whether the work was done already: $error',
      );
    }
  }

  /// Resets the steps from [fromStep] on, for [resume].
  Future<void> _rewind(String id, int fromStep) async {
    final steps = await _jobs.steps(id);
    if (fromStep < 0 || fromStep >= steps.length) {
      throw JobInvalidException(
        'Job $id has no step $fromStep; it has ${steps.length}.',
      );
    }
    final undone = steps.take(fromStep).where((s) => !s.state.isDone);
    if (undone.isNotEmpty) {
      throw JobInvalidException(
        'Step ${undone.first.ordinal} is ${undone.first.state.name}, so the '
        'job cannot resume from step $fromStep.',
      );
    }
    for (final step in steps.skip(fromStep)) {
      if (step.state == StepState.pending) continue;
      await _saveStep(
        step.copyWith(
          state: StepState.pending,
          result: null,
          message: null,
          pgid: null,
          startedAt: null,
          finishedAt: null,
        ),
      );
    }
  }

  // ---------------------------------------------------------------- helpers

  Future<JobRecord> _require(String id) async =>
      await _jobs.get(id) ?? (throw JobNotFoundException(id));

  Future<void> _saveJob(JobRecord job) async {
    await _jobs.updateJob(job);
    _announceJob(job);
  }

  void _announceJob(JobRecord job) => _events.append(
    JobStateChanged(jobId: job.id, projectId: job.projectId, state: job.state),
  );

  Future<void> _saveStep(StepRecord step, {bool announce = true}) async {
    await _jobs.updateStep(step);
    if (announce) {
      _events.append(
        JobStepChanged(
          jobId: step.jobId,
          ordinal: step.ordinal,
          kind: step.kind,
          state: step.state,
        ),
      );
    }
  }

  /// [text] with the secrets the engine knows hidden.
  String _mask(String text) {
    final masking = _supervisor.masker.newStream();
    return masking.add(text) + masking.flush();
  }

  String _hex(int bytes) => List.generate(
    bytes,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

/// Teaches [masker] the text of [bytes], if they are text. A binary secret,
/// a keystore, has nothing readable to hide.
void _maskReadable(OutputMasker masker, List<int> bytes) {
  try {
    final text = utf8.decode(bytes);
    if (text.isNotEmpty) masker.add(text);
  } on FormatException {
    // Binary.
  }
}

/// A job that runs now.
class _Run {
  final done = Completer<void>();
  bool cancelRequested = false;
  bool interruptRequested = false;
  SupervisedProcess? process;

  bool get stopping => cancelRequested || interruptRequested;
}

class _RunnerContext implements StepContext {
  new(this._runner, this._run, this.record);

  final JobRunner _runner;
  final _Run _run;

  /// The step as stored now.
  StepRecord record;

  @override
  String get jobId => record.jobId;

  @override
  int get ordinal => record.ordinal;

  @override
  bool get isStopping => _run.stopping;

  @override
  Future<ProcessExit> run(
    ProcessCommand command, {
    void Function(OutputLine line)? onLine,
  }) async {
    if (_run.stopping) return const ProcessExit(exitCode: -15, cancelled: true);
    final secretEnvironment = await _secretEnvironment(command);
    final process = await _runner._supervisor.start(
      ProcessSpec(
        command.executable,
        command.arguments,
        workingDirectory: command.workingDirectory,
        environment: {
          ...allowlistedEnvironment(
            _runner._hostEnvironment,
            passThrough: command.passThroughEnvironment,
            values: command.environment,
          ),
          ...secretEnvironment,
        },
      ),
    );
    _run.process = process;
    final log = await _runner._logs.openStep(jobId, ordinal, record.kind);
    record = record.copyWith(pgid: process.pid, logPath: log.path);
    await _runner._saveStep(record, announce: false);

    (Object, StackTrace)? parserError;
    final recording = _record(
      process.output.subscribe(),
      log,
      onLine == null
          ? null
          : (line) {
              try {
                onLine(line);
              } on Object catch (error, stackTrace) {
                parserError ??= (error, stackTrace);
              }
            },
    );
    if (_run.stopping) unawaited(process.cancel());
    try {
      final exit = await process.run();
      await recording;
      if (parserError case (final Object error, final StackTrace stackTrace)) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      return exit;
    } finally {
      _run.process = null;
      await log.close();
    }
  }

  Future<void> _record(
    Stream<OutputLine> lines,
    StepLog log,
    void Function(OutputLine line)? onLine,
  ) async {
    await for (final line in lines) {
      await log.record(line);
      onLine?.call(line);
    }
  }

  /// The secrets of [command] as environment variables: the values of the
  /// `secretEnvironment` ones, the paths of the files for `secretFiles` (a
  /// file holds the exact bytes of the secret, so a keystore stays binary).
  Future<Map<String, String>> _secretEnvironment(ProcessCommand command) async {
    final environment = <String, String>{};
    final masker = _runner._supervisor.masker;
    for (final (names, asFile) in [
      (command.secretEnvironment, false),
      (command.secretFiles, true),
    ]) {
      for (final MapEntry(key: variable, value: secretKey) in names.entries) {
        if (!_variableName.hasMatch(variable)) {
          throw ArgumentError.value(
            variable,
            'secret variable',
            'Not a valid environment variable name',
          );
        }
        if (asFile) {
          final bytes = await _runner._secrets.readBytes(secretKey);
          if (bytes == null) {
            throw SecretStoreException('There is no secret "$secretKey".');
          }
          _maskReadable(masker, bytes);
          environment[variable] = await _runner._secretFiles.writeBytes(
            jobId,
            '$ordinal-$variable',
            bytes,
          );
        } else {
          final value = await _runner._secrets.read(secretKey);
          if (value == null) {
            throw SecretStoreException('There is no secret "$secretKey".');
          }
          masker.add(value);
          environment[variable] = value;
        }
      }
    }
    return environment;
  }
}

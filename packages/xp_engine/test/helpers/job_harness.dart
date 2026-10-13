import 'dart:async';

import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

/// A [SecretStore] in memory.
class MemorySecretStore implements SecretStore {
  /// What is stored, by key.
  final values = <String, String>{};

  @override
  SecretsStatus get status => SecretsStatus.unlocked;

  @override
  Stream<SecretsStatus> get statusChanges => const Stream.empty();

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// An [OutputMasker] that replaces the secrets it knows within each piece.
class ReplacingMasker implements OutputMasker {
  /// The secrets it was told about.
  final secrets = <String>[];

  @override
  void add(String secret) => secrets.add(secret);

  @override
  StreamMasker newStream() => _ReplacingStream(this);
}

class _ReplacingStream implements StreamMasker {
  new(this._masker);

  final ReplacingMasker _masker;

  @override
  String add(String piece) => _masker.secrets.fold(
    piece,
    (text, secret) => text.replaceAll(secret, '***'),
  );

  @override
  String flush() => '';
}

/// A step that does what the test says.
class ScriptedStep extends Step<Map<String, dynamic>, Map<String, dynamic>> {
  /// Creates a step of [kind].
  new({
    this.kind = 'scripted',
    this.onRun,
    this.onAlreadyDone,
    this.encodeFails = false,
  });

  @override
  final String kind;

  /// What [run] does; by default it succeeds with `{'ran': true}`.
  final Future<StepOutcome<Map<String, dynamic>>> Function(
    Map<String, dynamic> input,
    StepContext context,
  )?
  onRun;

  /// What [alreadyDone] answers; by default `null`.
  final Future<Map<String, dynamic>?> Function(
    Map<String, dynamic> input,
    StepContext context,
  )?
  onAlreadyDone;

  /// Whether [encodeResult] throws.
  final bool encodeFails;

  /// The inputs of the calls to [run].
  final runs = <Map<String, dynamic>>[];

  /// The inputs of the calls to [alreadyDone].
  final checks = <Map<String, dynamic>>[];

  @override
  bool sideEffectOf(Map<String, dynamic> input) => input['sideEffect'] == true;

  @override
  Map<String, dynamic> decodeInput(Map<String, dynamic> json) {
    if (json['invalid'] == true) throw const FormatException('invalid input');
    return json;
  }

  @override
  Map<String, dynamic> encodeInput(Map<String, dynamic> input) => input;

  @override
  Map<String, dynamic> encodeResult(Map<String, dynamic> result) =>
      encodeFails ? throw StateError('cannot encode') : result;

  @override
  Future<Map<String, dynamic>?> alreadyDone(
    Map<String, dynamic> input,
    StepContext context,
  ) async {
    checks.add(input);
    return await onAlreadyDone?.call(input, context);
  }

  @override
  Future<StepOutcome<Map<String, dynamic>>> run(
    Map<String, dynamic> input,
    StepContext context,
  ) async {
    runs.add(input);
    return onRun == null
        ? const StepSucceeded({'ran': true})
        : await onRun!(input, context);
  }
}

/// A [JobRunner] over fakes, and the fakes.
class JobHarness {
  new _({
    required this.clock,
    required this.jobs,
    required this.events,
    required this.supervisor,
    required this.logStore,
    required this.logs,
    required this.secrets,
    required this.secretFiles,
    required this.power,
    required this.masker,
    required this.scripted,
    required this.runner,
    required this.errors,
  });

  factory create({
    FakeSupervisedHandler? handler,
    Map<String, String> environment = const {
      'PATH': '/usr/bin',
      'HOME': '/home/me',
      'GITHUB_TOKEN': 'ghp_must_not_leak',
    },
    JobRepository? repository,
    ScriptedStep? scripted,
    InMemorySecretFileStore? secretFiles,
  }) {
    final clock = ManualClock(DateTime.utc(2026, 10, 13, 9));
    final masker = ReplacingMasker();
    final supervisor = FakeProcessSupervisor(
      handler ?? ((process) => 0),
      clock: clock,
      masker: masker,
    );
    final jobs = repository ?? InMemoryJobRepository();
    final events = InMemoryEventLog(clock: clock, capacity: 10000);
    final logStore = InMemoryJobLogStore();
    final logs = JobLogs(store: logStore);
    final secrets = MemorySecretStore();
    final files = secretFiles ?? InMemorySecretFileStore();
    final power = NoPowerAssertion();
    final step = scripted ?? ScriptedStep();
    final errors = <Object>[];
    return JobHarness._(
      clock: clock,
      jobs: jobs,
      events: events,
      supervisor: supervisor,
      logStore: logStore,
      logs: logs,
      secrets: secrets,
      secretFiles: files,
      power: power,
      masker: masker,
      scripted: step,
      errors: errors,
      runner: JobRunner(
        jobs: jobs,
        steps: StepRegistry([const CommandStep(), step]),
        supervisor: supervisor,
        logs: logs,
        secrets: secrets,
        secretFiles: files,
        power: power,
        events: events,
        clock: clock,
        hostEnvironment: environment,
        onError: (error, _) => errors.add(error),
      ),
    );
  }

  final ManualClock clock;
  final JobRepository jobs;
  final InMemoryEventLog events;
  final FakeProcessSupervisor supervisor;
  final InMemoryJobLogStore logStore;
  final JobLogs logs;
  final MemorySecretStore secrets;
  final InMemorySecretFileStore secretFiles;
  final NoPowerAssertion power;
  final ReplacingMasker masker;
  final ScriptedStep scripted;
  final JobRunner runner;

  /// Failures the runner reported to `onError`.
  final List<Object> errors;

  /// A plan for a `command` step.
  StepPlan command(
    String executable, {
    List<String> arguments = const [],
    bool sideEffect = false,
    Map<String, String> secretEnvironment = const {},
    Map<String, String> secretFiles = const {},
    Map<String, String> environment = const {},
    List<String> passThrough = const [],
  }) => StepPlan.of(
    const CommandStep(),
    CommandInput(
      ProcessCommand(
        executable,
        arguments: arguments,
        environment: environment,
        passThroughEnvironment: passThrough,
        secretEnvironment: secretEnvironment,
        secretFiles: secretFiles,
      ),
      sideEffect: sideEffect,
    ),
  );

  /// A plan for a scripted step.
  StepPlan script({bool sideEffect = false, Map<String, dynamic>? input}) =>
      StepPlan.of(scripted, {'sideEffect': sideEffect, ...?input});

  /// Creates a job that runs [steps].
  Future<Job> create(List<StepPlan> steps) => runner.create(
    workflowVersionId: 'wfv_1',
    projectId: 'prj_1',
    sha: 'a' * 40,
    steps: steps,
  );

  /// Creates and starts a job, and waits for it to end.
  Future<Job> run(List<StepPlan> steps) async {
    final job = await create(steps);
    await runner.start(job.id);
    return await runner.whenFinished(job.id);
  }

  /// The job and step events logged so far, as `job <state>` and
  /// `step <ordinal> <state>`.
  Future<List<String>> jobEvents() async {
    final logged = <SequencedEvent>[];
    final subscription = events.subscribe(after: 0).listen(logged.add);
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();
    return [
      for (final entry in logged)
        switch (entry.event) {
          JobStateChanged(:final state) => 'job ${state.wire}',
          JobStepChanged(:final ordinal, :final state) =>
            'step $ordinal ${state.name}',
          _ => null,
        },
    ].nonNulls.toList();
  }

  /// The lines of the job as `step:text`.
  List<String> logLines(String jobId) => [
    for (final line in logStore.lines[jobId] ?? <LogLineFrame>[])
      '${line.step}:${line.text}',
  ];

  /// Waits until [condition] holds.
  Future<void> until(bool Function() condition) async {
    for (var i = 0; i < 1000 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    if (!condition()) throw StateError('Condition never held.');
  }
}

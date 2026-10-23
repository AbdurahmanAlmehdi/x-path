import 'dart:async';

import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import 'credential_harness.dart';
import 'job_harness.dart';

/// The results of the probe of a Mac: `git`, and Xcode if [xcode].
List<ProbeResult> macProbe({
  bool xcode = true,
  bool android = false,
  bool git = true,
}) => [
  const ProbeResult(
    id: 'os',
    status: ProbeStatus.exited,
    exitCode: 0,
    stdout: 'Darwin\n',
  ),
  ProbeResult(
    id: 'git',
    status: git ? ProbeStatus.exited : ProbeStatus.notStarted,
    exitCode: git ? 0 : null,
    stdout: 'git version 2.50.1\n',
  ),
  ProbeResult(
    id: 'android_sdk',
    status: ProbeStatus.exited,
    exitCode: android ? 0 : 1,
  ),
  javaProbe(),
  ProbeResult(
    id: 'xcode_select',
    status: xcode ? ProbeStatus.exited : ProbeStatus.notStarted,
    exitCode: xcode ? 0 : null,
    stdout: '/Applications/Xcode.app/Contents/Developer\n',
  ),
  ProbeResult(
    id: 'xcodebuild',
    status: xcode ? ProbeStatus.exited : ProbeStatus.skipped,
    exitCode: xcode ? 0 : null,
    stdout: xcode ? 'Xcode 26.1\nBuild version 17B55\n' : '',
  ),
  const ProbeResult(id: 'swift', status: ProbeStatus.skipped),
];

/// The result of the `java` probe command of a machine with JDK [version].
ProbeResult javaProbe([int version = 17]) => ProbeResult(
  id: 'java',
  status: ProbeStatus.exited,
  exitCode: 0,
  stderr: 'openjdk version "$version.0.12" 2024-07-16\n',
);

/// The results of the probe of a Linux machine.
List<ProbeResult> linuxProbe({bool android = true, bool swift = false}) => [
  const ProbeResult(
    id: 'os',
    status: ProbeStatus.exited,
    exitCode: 0,
    stdout: 'Linux\n',
  ),
  const ProbeResult(
    id: 'git',
    status: ProbeStatus.exited,
    exitCode: 0,
    stdout: 'git version 2.43.0\n',
  ),
  const ProbeResult(
    id: 'flutter_tools',
    status: ProbeStatus.exited,
    exitCode: 0,
  ),
  ProbeResult(
    id: 'android_sdk',
    status: ProbeStatus.exited,
    exitCode: android ? 0 : 1,
  ),
  javaProbe(),
  const ProbeResult(id: 'xcode_select', status: ProbeStatus.skipped),
  const ProbeResult(id: 'xcodebuild', status: ProbeStatus.skipped),
  ProbeResult(
    id: 'swift',
    status: swift ? ProbeStatus.exited : ProbeStatus.notStarted,
    exitCode: swift ? 0 : null,
  ),
];

/// A runner as the tests play it: it speaks the frames of the protocol to the
/// hub over a [FakeRunnerLink].
class FakeRunner {
  new _(this.h, this.record, this.link, this.connection);

  final RunnerHarness h;
  final RunnerRecord record;
  final FakeRunnerLink link;
  final RunnerConnection connection;

  /// The id of the runner.
  String get id => record.id;

  /// Sends [frame] and waits until the engine handled it.
  Future<void> send(RunnerFrame frame) => connection.receive(frame);

  /// Sends the hello.
  Future<void> hello({
    int cores = 8,
    int? maxJobs,
    bool draining = false,
    List<LeaseRef> leases = const [],
  }) => send(
    HelloFrame(
      version: '1.0.0',
      os: 'macos',
      arch: 'arm64',
      cores: cores,
      maxJobs: maxJobs,
      draining: draining,
      leases: leases,
    ),
  );

  /// Answers the probe the engine sent last with [results].
  Future<void> answerProbe(List<ProbeResult> results) => send(
    ProbeResultFrame(
      probeId: link.sentOf<ProbeFrame>().last.probeId,
      results: results,
    ),
  );

  /// Says hello and answers the probe: the runner is online.
  Future<void> online({
    List<ProbeResult>? results,
    int cores = 8,
    int? maxJobs,
  }) async {
    await hello(cores: cores, maxJobs: maxJobs);
    await answerProbe(results ?? macProbe());
  }

  /// The lease offers received so far.
  List<LeaseOfferFrame> get offers => link.sentOf<LeaseOfferFrame>();

  /// The offer received last.
  LeaseOfferFrame get offer => offers.last;

  /// The lease the offer [of] (the last by default) names.
  LeaseRef leaseOf([LeaseOfferFrame? of]) {
    final offer = of ?? this.offer;
    return LeaseRef(jobId: offer.jobId, leaseId: offer.leaseId);
  }

  /// Accepts the offer.
  Future<void> accept([LeaseOfferFrame? of]) {
    final lease = leaseOf(of);
    return send(LeaseAcceptFrame(jobId: lease.jobId, leaseId: lease.leaseId));
  }

  /// Sends a heartbeat for [leases], the lease of the last offer by default.
  Future<void> heartbeat([List<LeaseRef>? leases]) =>
      send(HeartbeatFrame(leases: leases ?? [leaseOf()]));

  /// Sends the chunk [seq] with [lines] of step [step].
  Future<void> chunk(
    int seq,
    List<String> lines, {
    int step = 0,
    LeaseRef? lease,
  }) {
    final ref = lease ?? leaseOf();
    return send(
      LogChunkFrame(
        jobId: ref.jobId,
        leaseId: ref.leaseId,
        seq: seq,
        lines: [
          for (final line in lines)
            ChunkLine(
              step: step,
              at: h.clock.now(),
              stream: LogStream.stdout,
              text: line,
            ),
        ],
      ),
    );
  }

  /// Reports step [ordinal].
  Future<void> step(
    int ordinal,
    StepState state, {
    int attempts = 1,
    Map<String, dynamic>? result,
    String? message,
    LeaseRef? lease,
  }) {
    final ref = lease ?? leaseOf();
    return send(
      StepStateFrame(
        jobId: ref.jobId,
        leaseId: ref.leaseId,
        ordinal: ordinal,
        state: state,
        attempts: attempts,
        result: result,
        message: message,
      ),
    );
  }

  /// Ends the job.
  Future<void> done(
    JobState state, {
    int lastChunk = 0,
    String? message,
    LeaseRef? lease,
  }) {
    final ref = lease ?? leaseOf();
    return send(
      JobDoneFrame(
        jobId: ref.jobId,
        leaseId: ref.leaseId,
        state: state,
        lastChunk: lastChunk,
        message: message,
      ),
    );
  }

  /// Asks for the secret [key].
  Future<void> secret(String key, {LeaseRef? lease}) {
    final ref = lease ?? leaseOf();
    return send(
      SecretRequestFrame(jobId: ref.jobId, leaseId: ref.leaseId, key: key),
    );
  }

  /// The acknowledgements of chunks received so far.
  List<ChunkAckFrame> get chunkAcks => link.sentOf<ChunkAckFrame>();

  /// The cancels received so far.
  List<CancelFrame> get cancels => link.sentOf<CancelFrame>();

  /// The faults received so far.
  List<FaultFrame> get faults => link.sentOf<FaultFrame>();
}

/// The hub, the service and the scheduler over fakes, and the runners that
/// play the other side.
class RunnerHarness {
  new _({
    required this.jobs,
    required this.clock,
    required this.runs,
    required this.scheduler,
    required this.runners,
    required this.pairing,
    required this.tokens,
    required this.secrets,
    required this.credentials,
    required this.projects,
    required this.hub,
    required this.service,
    required this.owner,
    required this.errors,
    required this.refused,
    required this.localGate,
  });

  static Future<RunnerHarness> create({
    Set<Capability> local = const {Capability.flutter},
    int localSlots = 1,
    JobRepository? jobRepository,
    JobLogs Function(JobLogStore store)? hubLogs,
    RunnerRepository Function(RunnerRepository inner)? wrapRunners,
  }) async {
    final errors = <Object>[];
    final refused = <String>[];
    final localGate = Completer<void>();
    final jobs = JobHarness.create(
      repository: jobRepository,
      scripted: ScriptedStep(
        onRun: (input, context) async {
          if (input['block'] == true) await localGate.future;
          return const StepSucceeded({'ran': true});
        },
      ),
    );
    final runs = InMemoryRunRepository();
    final scheduler = Scheduler(
      runner: jobs.runner,
      records: jobs.jobs,
      runs: runs,
      events: jobs.events,
      runners: [
        LocalRunner(jobs: jobs.runner, capabilities: local, slots: localSlots),
      ],
      onError: (error, _) => errors.add(error),
    );
    final runners = InMemoryRunnerRepository();
    final storedRunners = wrapRunners == null ? runners : wrapRunners(runners);
    final tokens = TokenService(
      tokens: InMemoryDeviceTokenRepository(),
      clock: jobs.clock,
    );
    final secrets = BytesSecretStore();
    final credentials = InMemoryCredentialRepository();
    final projects = InMemoryProjectRepository();
    await projects.add(
      ProjectRecord(
        id: 'prj_1',
        githubRepoId: 7,
        fullName: 'owner/app',
        remote: 'https://github.com/owner/app.git',
        githubDefaultBranch: 'main',
        scan: const ProjectProfile(),
        findings: const [],
        scannedAt: DateTime.utc(2026),
      ),
    );
    final hub = RunnerHub(
      runners: storedRunners,
      projects: projects,
      jobs: jobs.jobs,
      runner: jobs.runner,
      scheduler: scheduler,
      logs: hubLogs == null ? jobs.logs : hubLogs(jobs.logStore),
      events: jobs.events,
      clock: jobs.clock,
      secrets: secrets,
      masker: jobs.masker,
      grants: RunnerSecretGrants(credentials),
      engineVersion: '9.9.9',
      onError: (error, _) => errors.add(error),
      onRefused: (name, why) => refused.add('$name: $why'),
    );
    scheduler.remoteJobs = hub;
    final pairing = InMemoryPairingTokenRepository();
    final service = RunnerService(
      runners: storedRunners,
      pairing: pairing,
      tokens: tokens,
      presence: hub,
      settings: InMemoryEngineSettingRepository(),
      events: jobs.events,
      clock: jobs.clock,
    );
    final owner = (await tokens.issue(
      name: 'owner',
      kind: DeviceTokenKind.app,
    )).token;
    return RunnerHarness._(
      jobs: jobs,
      clock: jobs.clock,
      runs: runs,
      scheduler: scheduler,
      runners: runners,
      pairing: pairing,
      tokens: tokens,
      secrets: secrets,
      credentials: credentials,
      projects: projects,
      hub: hub,
      service: service,
      owner: owner,
      errors: errors,
      refused: refused,
      localGate: localGate,
    );
  }

  final JobHarness jobs;
  final ManualClock clock;
  final InMemoryRunRepository runs;
  final Scheduler scheduler;
  final InMemoryRunnerRepository runners;
  final InMemoryPairingTokenRepository pairing;
  final TokenService tokens;
  final BytesSecretStore secrets;
  final InMemoryCredentialRepository credentials;
  final InMemoryProjectRepository projects;
  final RunnerHub hub;
  final RunnerService service;
  final DeviceToken owner;

  /// Failures reported to `onError`; a test that expects none checks it.
  final List<Object> errors;

  /// What the hub reported as refused connections, as `name: why`.
  final List<String> refused;

  /// Local steps made with `block: true` wait for this.
  final Completer<void> localGate;

  var _runs = 0;
  var _runners = 0;

  /// Pairs a runner called [name] and opens its connection.
  Future<FakeRunner> pair([String? name]) async {
    final runnerName = name ?? 'runner-${++_runners}';
    final token = await service.createPairingToken(name: runnerName, by: owner);
    final paired = await service.pair(token.token);
    final record = (await runners.get(paired.runner.id))!;
    final link = FakeRunnerLink();
    return FakeRunner._(this, record, link, hub.connect(record, link));
  }

  /// Pairs a runner and has it say hello and answer the probe.
  Future<FakeRunner> online({
    String? name,
    List<ProbeResult>? results,
    int cores = 8,
    int? maxJobs,
  }) async {
    final runner = await pair(name);
    await runner.online(results: results, cores: cores, maxJobs: maxJobs);
    return runner;
  }

  /// Connects the runner again with a new connection, as the engine's route
  /// does: with the record as the engine stores it now.
  Future<FakeRunner> reconnect(FakeRunner runner) async {
    final record = (await runners.get(runner.id))!;
    final link = FakeRunnerLink();
    return FakeRunner._(this, record, link, hub.connect(record, link));
  }

  /// A plan for the scripted step. `block` makes it wait on the engine until
  /// [localGate] completes.
  StepPlan script({bool sideEffect = false, bool block = false}) =>
      jobs.script(sideEffect: sideEffect, input: {'block': block});

  /// Makes a run of one job of [steps] and returns the job's id.
  Future<String> job({
    List<StepPlan>? steps,
    List<String> needs = const [],
    int stage = 0,
    String project = 'prj_1',
    String? name,
  }) async {
    final runId = 'run_${++_runs}';
    clock.advance(const Duration(seconds: 1));
    await runs.create(
      RunRecord(
        id: runId,
        projectId: project,
        workflowId: 'wf_1',
        workflowVersionId: 'wfv_1',
        sha: 'a' * 40,
        locksProject: false,
        createdAt: clock.now(),
      ),
    );
    final job = await jobs.runner.create(
      workflowVersionId: 'wfv_1',
      projectId: project,
      sha: 'a' * 40,
      runId: runId,
      stage: stage,
      name: name ?? 'job $_runs',
      capabilities: needs,
      steps: steps ?? [script()],
    );
    return job.id;
  }

  /// The job [id] as the engine stores it.
  Future<JobRecord> record(String id) async => (await jobs.jobs.get(id))!;

  /// The state of the job [id].
  Future<JobState> state(String id) async => (await record(id)).state;

  /// The steps of the job [id].
  Future<List<StepRecord>> steps(String id) => jobs.jobs.steps(id);

  /// The events logged so far.
  Future<List<EngineEvent>> events() async {
    final logged = <SequencedEvent>[];
    final subscription = jobs.events.subscribe(after: 0).listen(logged.add);
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();
    return [for (final entry in logged) entry.event];
  }

  /// The events of type [T] logged so far.
  Future<List<T>> eventsOf<T extends EngineEvent>() async =>
      (await events()).whereType<T>().toList();

  /// Lets the engine's tasks run.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 2));
}

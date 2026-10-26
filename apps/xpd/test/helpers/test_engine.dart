import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:async/async.dart';
import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xpd/xpd.dart';

import 'credential_fakes.dart';
import 'job_fakes.dart';
import 'project_fakes.dart';

/// The files of a minimal Flutter app: the folder every test project is added
/// from.
const projectFiles = {
  'pubspec.yaml': '''
name: demo
version: 1.0.0+1
dependencies:
  flutter:
    sdk: flutter
''',
  'lib/main.dart': '',
  '.fvmrc': '{"flutter": "3.47.4"}',
  'android/app/build.gradle': 'defaultConfig { applicationId "com.example" }',
};

/// A response read to the end.
class RawResponse {
  const new(
    this.statusCode,
    this.contentType,
    this.body, [
    this.headers = const {},
  ]);

  final int statusCode;
  final String? contentType;
  final String body;

  /// The headers of the response, by lower-case name.
  final Map<String, String> headers;

  Map<String, dynamic> get json => jsonDecode(body) as Map<String, dynamic>;
}

/// A response read to the end as bytes.
class RawBytes {
  const new(this.statusCode, this.headers, this.bytes);

  final int statusCode;
  final HttpHeaders headers;
  final List<int> bytes;

  String get text => utf8.decode(bytes);
}

/// A repository that cannot be read, so that every authenticated request
/// fails inside the engine.
class ThrowingDeviceTokenRepository implements DeviceTokenRepository {
  @override
  Future<List<DeviceToken>> list() async => throw StateError('disk on fire');

  @override
  Future<void> add(DeviceToken token) async {}

  @override
  Future<bool> revoke(String id, {required DateTime at}) async => false;
}

/// Build number counters for any app: the first number of an app is 1.
class _AutoCounters implements BuildCounterRepository {
  final _counters = <(String, String), int>{};

  @override
  Future<int> allocate({
    required String projectId,
    required String appPath,
    required int seed,
  }) async {
    return _counters[(projectId, appPath)] = await peek(
      projectId: projectId,
      appPath: appPath,
      seed: seed,
    );
  }

  @override
  Future<int> peek({
    required String projectId,
    required String appPath,
    required int seed,
  }) async {
    final current = _counters[(projectId, appPath)] ?? 0;
    return (current > seed ? current : seed) + 1;
  }
}

/// An engine on a free loopback port with everything in memory.
class TestEngine {
  new _({
    required this.server,
    required this.events,
    required this.clock,
    required this.tokens,
    required this.secret,
    required this.errors,
    required this.github,
    required this.git,
    required this.folders,
    required this.jobs,
    required this.jobRepository,
    required this.supervisor,
    required this.logStore,
    required this.logs,
    required this.artifactRepository,
    required this.artifactStore,
    required this.testRuns,
    required this.projectRepository,
    required this.credentialRepository,
    required this.credentialSecrets,
    required this.credentialVerifiers,
    required this.appStoreConnect,
    required this.masker,
    required this.scheduler,
    required this.runRepository,
    required this.workflowRepository,
    required this.gate,
    required this.approvals,
    required this.approvalRepository,
    required this.releaseService,
    required this.releaseRepository,
    required this.appleStatus,
    required this.playStatus,
    required this.shorebirdRecords,
    required this.dataFiles,
    required this.housekeepingSettings,
    required this.runnerRepository,
    required this.runnerHub,
    required this.runnerService,
    required this.runnerBundles,
    required this.githubCli,
  });

  static Future<TestEngine> start({
    int eventCapacity = 100,
    EventLog Function(EventLog log)? wrapLog,
    DeviceTokenRepository? repository,
    ProjectRepository? projectRepository,
    JobLogStore? logStore,
    int logLiveCapacity = 1024,
    bool realApprovals = false,
  }) async {
    const repo = GitHubRepo(
      id: 42,
      fullName: 'octo/app',
      defaultBranch: 'main',
      cloneUrl: 'https://github.com/octo/app.git',
    );
    final github = FakeGitHub({42: repo});
    final git = FakeGit();
    final folders = <String, Map<String, String>>{};
    final clock = ManualClock(DateTime.utc(2026, 10, 13, 9));
    final log = InMemoryEventLog(clock: clock, capacity: eventCapacity);
    final tokens = TokenService(
      tokens: repository ?? InMemoryDeviceTokenRepository(),
      clock: clock,
    );
    final errors = <Object>[];
    final jobRepository = InMemoryJobRepository();
    final artifactRepository = InMemoryArtifactRepository();
    final artifactStore = InMemoryArtifactStore();
    final testRuns = InMemoryTestRunRepository();
    final projects = projectRepository ?? InMemoryProjectRepository();
    final supervisor = FakeProcessSupervisor((process) => 0, clock: clock);
    final store = logStore ?? InMemoryJobLogStore();
    final logs = JobLogs(store: store, liveCapacity: logLiveCapacity);
    final events = wrapLog == null ? log : wrapLog(log);
    final credentialRepository = InMemoryCredentialRepository();
    final credentialSecrets = BytesSecretStore();
    final credentialVerifiers = {
      for (final kind in CredentialKind.values)
        kind: FakeCredentialVerifier(kind),
    };
    final masker = RecordingMasker();
    final gate = FakeApprovalGate();
    late final Scheduler scheduler;
    final approvalRepository = InMemoryApprovalRepository();
    final gateConfigs = InMemoryGateConfigRepository();
    final approvals = ApprovalService(
      approvals: approvalRepository,
      gates: gateConfigs,
      projects: projects,
      jobs: jobRepository,
      events: events,
      clock: clock,
      resume: (projectId) => scheduler.resumeWaiting(projectId: projectId),
    );
    final releaseRepository = InMemoryReleaseRepository();
    final registry = StepRegistry([
      const CommandStep(),
      GateStep(realApprovals ? approvals : gate),
      GitCheckoutStep(git: git, jobs: jobRepository),
      VersionBumpStep(git: git, workspaces: (_) => InMemoryWorkspace(const {})),
      GitHubCreatePrStep(github),
      GitHubMergePrStep(github: github, releases: releaseRepository),
      StoreRolloutStep(
        releases: releaseRepository,
        ascCredentials: FakeAscCredentialSource(),
        appStoreConnect: (_) => FakeAppStoreConnect(),
        playCredentials: FakePlayCredentialSource(),
        googlePlay: (_) => FakeGooglePlay(),
      ),
      ShorebirdTrackStep(FakeShorebirdPatches()),
    ]);
    final jobs = JobRunner(
      jobs: jobRepository,
      steps: registry,
      supervisor: supervisor,
      logs: logs,
      secrets: MemorySecretStore(),
      secretFiles: InMemorySecretFileStore(),
      power: NoPowerAssertion(),
      events: events,
      clock: clock,
      hostEnvironment: const {'PATH': '/usr/bin'},
      onError: (error, _) => errors.add(error),
    );
    final runRepository = InMemoryRunRepository();
    scheduler = Scheduler(
      runner: jobs,
      records: jobRepository,
      runs: runRepository,
      events: events,
      runners: [
        LocalRunner(
          jobs: jobs,
          capabilities: const {Capability.flutter},
          slots: 2,
        ),
      ],
      onError: (error, _) => errors.add(error),
    );
    final planners = StepPlanners(registry);
    final workflowRepository = InMemoryWorkflowRepository();
    final workflows = WorkflowService(
      repository: workflowRepository,
      projects: projects,
      catalog: planners,
      events: events,
      clock: clock,
    );
    final runService = RunService(
      runs: runRepository,
      jobs: jobRepository,
      control: scheduler,
    );
    final appleStatus = FakeStoreStatusSource(ReleaseStore.apple);
    final playStatus = FakeStoreStatusSource(ReleaseStore.play);
    late final WorkflowDispatcher dispatcher;
    final releaseService = ReleaseService(
      releases: releaseRepository,
      jobs: jobRepository,
      runRecords: runRepository,
      runs: runService,
      workflows: workflows,
      poller: ReleaseStatusPoller(
        sources: [appleStatus, playStatus],
        clock: clock,
      ),
      events: events,
      clock: clock,
      dispatch: (projectId, workflowId, request) =>
          dispatcher.dispatch(projectId, workflowId, request),
    );
    dispatcher = WorkflowDispatcher(
      workflows: workflows,
      planners: planners,
      projects: projects,
      credentials: credentialRepository,
      models: DefaultReleaseModels(),
      git: git,
      allocator: BuildNumberAllocator(
        counters: _AutoCounters(),
        stores: FakeStoreBuildNumbers(),
        git: git,
      ),
      jobs: jobs,
      records: jobRepository,
      runs: runRepository,
      scheduler: scheduler,
      events: events,
      clock: clock,
      workspaces: (_) => InMemoryWorkspace(const {
        'pubspec.yaml': 'name: demo\nversion: 1.0.0+1\n',
      }),
      worktreeAt: (mirror, name) => '/worktrees/$name',
      releases: releaseService,
      gates: gateConfigs,
    );
    final runnerRepository = InMemoryRunnerRepository();
    final runnerHub = RunnerHub(
      runners: runnerRepository,
      projects: projects,
      jobs: jobRepository,
      runner: jobs,
      scheduler: scheduler,
      logs: logs,
      events: events,
      clock: clock,
      secrets: credentialSecrets,
      masker: masker,
      grants: RunnerSecretGrants(credentialRepository),
      engineVersion: '9.9.9',
      onError: (error, _) => errors.add(error),
    );
    scheduler.remoteJobs = runnerHub;
    final runnerService = RunnerService(
      runners: runnerRepository,
      pairing: InMemoryPairingTokenRepository(),
      tokens: tokens,
      presence: runnerHub,
      settings: InMemoryEngineSettingRepository(),
      events: events,
      clock: clock,
    );
    final shorebirdRecords = InMemoryShorebirdReleaseRepository();
    final dataFiles = InMemoryDataFiles();
    final housekeepingSettings = InMemoryHousekeepingRepository();
    final housekeeping = HousekeepingService(
      planner: HousekeepingPlanner(
        artifacts: artifactRepository,
        jobs: jobRepository,
        releases: releaseRepository,
        projects: projects,
        testRuns: testRuns,
        shorebird: shorebirdRecords,
        files: dataFiles,
        clock: clock,
      ),
      settings: housekeepingSettings,
      artifacts: artifactRepository,
      store: artifactStore,
      jobs: jobRepository,
      files: dataFiles,
      clock: clock,
    );
    final runnerBundles = InMemoryRunnerBundles();
    final githubCli = FakeGitHubCliToken();
    final issued = await tokens.issue(name: 'test', kind: DeviceTokenKind.app);
    final githubToken = GitHubTokenService(
      secrets: credentialSecrets,
      verifier: credentialVerifiers[CredentialKind.github]!,
      cli: githubCli,
      masker: masker,
    );
    final credentialService = CredentialService(
      repository: credentialRepository,
      projects: projects,
      secrets: credentialSecrets,
      verifiers: credentialVerifiers.values,
      masker: masker,
      events: events,
      clock: clock,
    );
    final appStoreConnect = FakeAppStoreConnect();
    final server = await XpdServer.start(
      tokens: tokens,
      events: events,
      projects: ProjectService(
        repository: projects,
        github: github,
        git: git,
        scanner: const ProjectScanner(),
        // A folder is its files in `folders`; a worktree is a plain app.
        sources: (directory) => InMemoryScanSource(
          directory.startsWith('/worktrees/')
              ? projectFiles
              : folders[directory] ?? {},
        ),
        // Every clone has the same `origin`.
        runner: FakeProcessRunner(
          (call) => const ProcessOutput(
            exitCode: 0,
            stdout: 'git@github.com:octo/app.git\n',
          ),
        ),
        events: events,
        clock: clock,
      ),
      jobs: scheduler,
      logs: logs,
      artifacts: ArtifactService(
        repository: artifactRepository,
        store: artifactStore,
        jobs: jobRepository,
      ),
      tests: TestRunService(
        runs: testRuns,
        jobs: jobRepository,
        projects: projects,
      ),
      credentials: credentialService,
      certificates: DistributionCertificates(
        credentials: credentialService,
        repository: credentialRepository,
        secrets: credentialSecrets,
        connect: (_) => appStoreConnect,
        keys: const RsaDistributionKeys(bits: 512),
      ),
      githubToken: githubToken,
      workflows: workflows,
      dispatcher: dispatcher,
      runs: runService,
      approvals: approvals,
      releases: releaseService,
      releaseNotes: ReleaseNotesService(
        releases: releaseRepository,
        projects: projects,
        models: DefaultReleaseModels(),
        git: git,
      ),
      housekeeping: housekeeping,
      runners: runnerService,
      runnerHub: runnerHub,
      runnerArtifacts: RunnerArtifacts(
        recorder: ArtifactRecorder(
          store: artifactStore,
          repository: artifactRepository,
          clock: clock,
        ),
        holdsLease: runnerHub.holdsLease,
      ),
      runnerBundles: runnerBundles,
      // The engine's own runner: Android and Flutter, no iOS signing.
      doctor: EngineDoctor(
        local: const ProbeFindings(
          capabilities: {Capability.android, Capability.flutter},
          missing: [
            MissingCapability(
              capability: 'ios-sign',
              reason: 'not macOS',
              fix: 'run the engine on a Mac',
            ),
          ],
        ),
        github: githubToken,
        credentials: credentialRepository,
        projects: projects,
        runner: FakeProcessRunner(
          (call) => const ProcessOutput(exitCode: 1, stderr: 'Hi octo!\n'),
        ),
      ),
      secrets: credentialSecrets,
      clock: clock,
      engineVersion: '9.9.9',
      onError: (error, _) => errors.add(error),
    );
    return ._(
      server: server,
      events: log,
      clock: clock,
      tokens: tokens,
      secret: issued.secret,
      errors: errors,
      github: github,
      git: git,
      folders: folders,
      jobs: jobs,
      jobRepository: jobRepository,
      supervisor: supervisor,
      logStore: store,
      logs: logs,
      artifactRepository: artifactRepository,
      artifactStore: artifactStore,
      testRuns: testRuns,
      projectRepository: projects,
      credentialRepository: credentialRepository,
      credentialSecrets: credentialSecrets,
      credentialVerifiers: credentialVerifiers,
      appStoreConnect: appStoreConnect,
      masker: masker,
      scheduler: scheduler,
      runRepository: runRepository,
      workflowRepository: workflowRepository,
      gate: gate,
      approvals: approvals,
      approvalRepository: approvalRepository,
      releaseService: releaseService,
      releaseRepository: releaseRepository,
      appleStatus: appleStatus,
      playStatus: playStatus,
      shorebirdRecords: shorebirdRecords,
      dataFiles: dataFiles,
      housekeepingSettings: housekeepingSettings,
      runnerRepository: runnerRepository,
      runnerHub: runnerHub,
      runnerService: runnerService,
      runnerBundles: runnerBundles,
      githubCli: githubCli,
    );
  }

  final XpdServer server;
  final FakeGitHub github;
  final FakeGit git;
  final JobRunner jobs;
  final InMemoryJobRepository jobRepository;
  final FakeProcessSupervisor supervisor;
  final JobLogStore logStore;
  final JobLogs logs;
  final InMemoryArtifactRepository artifactRepository;
  final InMemoryArtifactStore artifactStore;
  final InMemoryTestRunRepository testRuns;
  final ProjectRepository projectRepository;

  /// The credential references; add the flavors credentials can be saved for.
  final InMemoryCredentialRepository credentialRepository;

  /// The secrets of the credentials.
  final BytesSecretStore credentialSecrets;

  /// The check of each kind of credential; they accept everything by default.
  final Map<CredentialKind, FakeCredentialVerifier> credentialVerifiers;

  /// The App Store Connect the engine creates distribution certificates
  /// with.
  final FakeAppStoreConnect appStoreConnect;

  /// What the engine was told to hide in logs.
  final RecordingMasker masker;

  /// Starts the queued jobs of runs.
  final Scheduler scheduler;

  /// The runs.
  final InMemoryRunRepository runRepository;

  /// The workflows.
  final InMemoryWorkflowRepository workflowRepository;

  /// What the gates of workflows ask; it leaves them pending until told.
  /// (Unless the engine was started with `realApprovals`: then they ask
  /// [approvals].)
  final FakeApprovalGate gate;

  /// The approvals and gates of the engine.
  final ApprovalService approvals;

  /// Where the approvals are kept.
  final InMemoryApprovalRepository approvalRepository;

  /// The releases of the engine.
  final ReleaseService releaseService;

  /// Where the releases are kept.
  final InMemoryReleaseRepository releaseRepository;

  /// What App Store Connect says about a release; it cannot be read until the
  /// test gives it an answer.
  final FakeStoreStatusSource appleStatus;

  /// What Google Play says about a release.
  final FakeStoreStatusSource playStatus;

  /// The Shorebird releases the engine knows.
  final InMemoryShorebirdReleaseRepository shorebirdRecords;

  /// The folders of the data directory that housekeeping looks after.
  final InMemoryDataFiles dataFiles;

  /// Where housekeeping keeps its settings.
  final InMemoryHousekeepingRepository housekeepingSettings;

  /// The runners of the engine.
  final InMemoryRunnerRepository runnerRepository;

  /// The connections and leases of the runners.
  final RunnerHub runnerHub;

  /// Pairs, lists and revokes runners.
  final RunnerService runnerService;

  /// The runner bundles the engine hands out.
  final InMemoryRunnerBundles runnerBundles;

  /// The GitHub CLI of the engine machine (`POST /github-token/import`).
  /// The GitHub token itself is checked by
  /// `credentialVerifiers[CredentialKind.github]` and kept in
  /// [credentialSecrets].
  final FakeGitHubCliToken githubCli;

  /// The files of the folders a project can be added from, by path.
  final Map<String, Map<String, String>> folders;
  final InMemoryEventLog events;
  final ManualClock clock;
  final TokenService tokens;

  /// A valid `app` token.
  final String secret;

  /// Exceptions that became 500 responses.
  final List<Object> errors;

  Uri get uri => server.uri;

  Future<void> close() => server.close();

  /// Sends a plain request. Sends the valid token unless [token] is given;
  /// pass an empty string for no `Authorization` header.
  Future<RawResponse> request(
    String path, {
    String method = 'GET',
    String? token,
    Map<String, String> headers = const {},
    String? body,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(method, uri.resolve(path));
      final bearer = token ?? secret;
      if (bearer.isNotEmpty) {
        request.headers.set('authorization', 'Bearer $bearer');
      }
      headers.forEach(request.headers.set);
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(body);
      }
      final response = await request.close();
      final received = <String, String>{};
      response.headers.forEach((name, values) => received[name] = values.first);
      return RawResponse(
        response.statusCode,
        response.headers.contentType?.toString(),
        await utf8.decodeStream(response),
        received,
      );
    } finally {
      client.close(force: true);
    }
  }

  /// Downloads [path] as bytes, with the headers of the response.
  Future<RawBytes> download(String path, {String? token}) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri.resolve(path));
      final bearer = token ?? secret;
      if (bearer.isNotEmpty) {
        request.headers.set('authorization', 'Bearer $bearer');
      }
      final response = await request.close();
      return RawBytes(
        response.statusCode,
        response.headers,
        await response.expand((chunk) => chunk).toList(),
      );
    } finally {
      client.close(force: true);
    }
  }

  /// Stores an artifact of [jobId] with [content], the way a build step does.
  Future<ArtifactRecord> addArtifact(
    String jobId, {
    String name = 'dev-1.0.0+1.apk',
    ArtifactKind kind = ArtifactKind.apk,
    String content = 'apk bytes',
  }) async {
    final recorder = ArtifactRecorder(
      store: artifactStore,
      repository: artifactRepository,
      clock: clock,
    );
    return await recorder.record(
      jobId: jobId,
      kind: kind,
      name: name,
      content: Stream.value(utf8.encode(content)),
    );
  }

  /// Like [request] but with the headers of a WebSocket handshake, so that the
  /// engine answers with the real status instead of 426.
  Future<RawResponse> handshake(String path, {String? token}) => request(
    path,
    token: token,
    headers: {
      'connection': 'Upgrade',
      'upgrade': 'websocket',
      'sec-websocket-version': '13',
      'sec-websocket-key': base64.encode(List.filled(16, 7)),
    },
  );

  /// Creates a job with one `command` step per executable and starts it.
  Future<Job> startJob(List<String> executables) async {
    final job = await createJob(executables);
    await jobs.start(job.id);
    return job;
  }

  /// Creates a queued job with one `command` step per executable.
  Future<Job> createJob(List<String> executables, {bool sideEffect = false}) =>
      jobs.create(
        workflowVersionId: 'wfv_1',
        projectId: 'prj_1',
        steps: [
          for (final executable in executables)
            StepPlan.of(
              const CommandStep(),
              CommandInput(ProcessCommand(executable), sideEffect: sideEffect),
            ),
        ],
      );

  /// Opens the log stream of a job.
  Future<JobLogStream> connectLogs(
    String jobId, {
    int? after,
    String? token,
  }) async {
    final query = after == null ? '' : '?after=$after';
    final bearer = token ?? secret;
    final socket = await WebSocket.connect(
      'ws://127.0.0.1:${uri.port}/jobs/$jobId/logs$query',
      headers: {if (bearer.isNotEmpty) 'authorization': 'Bearer $bearer'},
    );
    return JobLogStream(socket);
  }

  /// Opens the connection of a runner with [token] as its credential.
  Future<RunnerStream> connectRunner({String? token}) async {
    final bearer = token ?? secret;
    final socket = await WebSocket.connect(
      'ws://127.0.0.1:${uri.port}/runners/connect',
      headers: {if (bearer.isNotEmpty) 'authorization': 'Bearer $bearer'},
    );
    return RunnerStream(socket);
  }

  /// The events of type [T] logged so far.
  Future<List<T>> eventsOf<T extends EngineEvent>() async {
    final logged = <SequencedEvent>[];
    final subscription = events.subscribe(after: 0).listen(logged.add);
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();
    return [
      for (final entry in logged) ?(entry.event is T ? entry.event as T : null),
    ];
  }

  /// Makes a token of [kind] and returns its secret.
  Future<String> tokenOf(DeviceTokenKind kind) async =>
      (await tokens.issue(name: kind.name, kind: kind)).secret;

  /// Pairs a runner called [name] and returns its credential.
  Future<({Runner runner, String token})> pairRunner([
    String name = 'mac-mini',
  ]) async {
    final owner = (await tokens.authenticate(secret))!;
    final pairing = await runnerService.createPairingToken(
      name: name,
      by: owner,
    );
    final paired = await runnerService.pair(pairing.token);
    return (runner: paired.runner, token: paired.token);
  }

  /// Opens the event stream.
  Future<EventStream> connect({int? after, String? token}) async {
    final query = after == null ? '' : '?after=$after';
    final bearer = token ?? secret;
    final socket = await WebSocket.connect(
      'ws://127.0.0.1:${uri.port}/events$query',
      headers: {if (bearer.isNotEmpty) 'authorization': 'Bearer $bearer'},
    );
    return EventStream(socket);
  }
}

/// The frames of one `/events` connection.
class EventStream {
  new(this.socket)
    : _frames = StreamQueue(
        socket.map(
          (frame) => SequencedEvent.fromJson(
            jsonDecode(frame as String) as Map<String, dynamic>,
          ),
        ),
      );

  final WebSocket socket;
  final StreamQueue<SequencedEvent> _frames;

  /// The next event, failing the test if none arrives.
  Future<SequencedEvent> next() =>
      _frames.next.timeout(const Duration(seconds: 5));

  /// The next [count] events.
  Future<List<SequencedEvent>> take(int count) async => [
    for (var i = 0; i < count; i++) await next(),
  ];

  /// Waits for the engine to close the socket and returns its close code.
  Future<int?> closeCode() async {
    expect(
      await _frames.hasNext.timeout(const Duration(seconds: 5)),
      isFalse,
      reason: 'the engine sent another frame instead of closing',
    );
    return socket.closeCode;
  }

  Future<void> close() async {
    await socket.close();
    await _frames.cancel(immediate: true);
  }
}

/// The frames of one `/runners/connect` connection, as the runner sees them.
class RunnerStream {
  new(this.socket)
    : _frames = StreamQueue(
        socket.map(
          (frame) => EngineFrame.fromJson(
            jsonDecode(frame as String) as Map<String, dynamic>,
          ),
        ),
      );

  final WebSocket socket;
  final StreamQueue<EngineFrame> _frames;

  /// Sends a frame to the engine.
  void send(RunnerFrame frame) => socket.add(jsonEncode(frame.toJson()));

  /// Sends text as it is.
  void sendText(String text) => socket.add(text);

  /// The next frame, failing the test if none arrives.
  Future<EngineFrame> next() =>
      _frames.next.timeout(const Duration(seconds: 5));

  /// The next frame of type [T], skipping others.
  Future<T> nextOf<T extends EngineFrame>() async {
    while (true) {
      final frame = await next();
      if (frame is T) return frame;
    }
  }

  /// Waits for the engine to close the socket and returns its close code.
  Future<int?> closeCode() async {
    while (await _frames.hasNext.timeout(const Duration(seconds: 5))) {
      await _frames.next;
    }
    return socket.closeCode;
  }

  Future<void> close() async {
    await socket.close();
    await _frames.cancel(immediate: true);
  }
}

/// The frames of one `/jobs/{id}/logs` connection.
class JobLogStream {
  new(this.socket)
    : _frames = StreamQueue(
        socket.map(
          (frame) => LogFrame.fromJson(
            jsonDecode(frame as String) as Map<String, dynamic>,
          ),
        ),
      );

  final WebSocket socket;
  final StreamQueue<LogFrame> _frames;

  /// The next frame, failing the test if none arrives.
  Future<LogFrame> next() => _frames.next.timeout(const Duration(seconds: 5));

  /// Every frame up to the end of the stream.
  Future<List<LogFrame>> all() async {
    final frames = <LogFrame>[];
    while (await _frames.hasNext.timeout(const Duration(seconds: 5))) {
      frames.add(await _frames.next);
    }
    return frames;
  }

  /// The code the engine closed the socket with, once it did.
  int? get closeCode => socket.closeCode;

  Future<void> close() async {
    await socket.close();
    await _frames.cancel(immediate: true);
  }
}

/// A [StringSink] that tells when something was written.
class WatchedSink implements StringSink {
  final _buffer = StringBuffer();
  final _waiters = <(Pattern, Completer<void>)>[];

  @override
  String toString() => _buffer.toString();

  /// Completes once the text written so far matches [pattern].
  Future<void> until(Pattern pattern) {
    if (_buffer.toString().contains(pattern)) return Future.value();
    final completer = Completer<void>();
    _waiters.add((pattern, completer));
    return completer.future.timeout(const Duration(seconds: 10));
  }

  @override
  void write(Object? object) {
    _buffer.write(object);
    final text = _buffer.toString();
    _waiters.removeWhere((waiter) {
      final matched = text.contains(waiter.$1);
      if (matched) waiter.$2.complete();
      return matched;
    });
  }

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      write(objects.join(separator));

  @override
  void writeCharCode(int charCode) => write(String.fromCharCode(charCode));

  @override
  void writeln([Object? object = '']) => write('$object\n');
}

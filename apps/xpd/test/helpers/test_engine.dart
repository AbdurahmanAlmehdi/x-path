import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:async/async.dart';
import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';
import 'package:xpd/xpd.dart';

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
  const new(this.statusCode, this.contentType, this.body);

  final int statusCode;
  final String? contentType;
  final String body;

  Map<String, dynamic> get json => jsonDecode(body) as Map<String, dynamic>;
}

/// A repository that cannot be read, so that every authenticated request
/// fails inside the engine.
class ThrowingDeviceTokenRepository implements DeviceTokenRepository {
  @override
  Future<List<DeviceToken>> list() async => throw StateError('disk on fire');

  @override
  Future<void> add(DeviceToken token) async {}
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
  });

  static Future<TestEngine> start({
    int eventCapacity = 100,
    EventLog Function(EventLog log)? wrapLog,
    DeviceTokenRepository? repository,
    ProjectRepository? projectRepository,
    JobLogStore? logStore,
    int logLiveCapacity = 1024,
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
    final supervisor = FakeProcessSupervisor((process) => 0, clock: clock);
    final store = logStore ?? InMemoryJobLogStore();
    final logs = JobLogs(store: store, liveCapacity: logLiveCapacity);
    final events = wrapLog == null ? log : wrapLog(log);
    final jobs = JobRunner(
      jobs: jobRepository,
      steps: StepRegistry([const CommandStep()]),
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
    final issued = await tokens.issue(name: 'test', kind: DeviceTokenKind.app);
    final server = await XpdServer.start(
      tokens: tokens,
      events: events,
      projects: ProjectService(
        repository: projectRepository ?? InMemoryProjectRepository(),
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
      jobs: jobs,
      logs: logs,
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
      return RawResponse(
        response.statusCode,
        response.headers.contentType?.toString(),
        await utf8.decodeStream(response),
      );
    } finally {
      client.close(force: true);
    }
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

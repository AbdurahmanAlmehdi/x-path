import 'dart:convert';

import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import 'test_engine.dart';
import 'workflow_helpers.dart';

/// The workflow the releases of the tests were made by: it checks out and bumps
/// the version.
const releaseWorkflow = '''
schema: 1
lock: project
stages:
  - name: build
    jobs:
      job:
        steps:
          - kind: git.checkout
          - kind: version.bump
''';

/// The upload steps of a flavor that goes to both stores.
List<StepPlan> uploadPlans({String version = '1.2.0+5'}) => [
  StepPlan(
    kind: 'upload.appStore',
    sideEffect: true,
    input: {
      'artifactName': 'default-$version.ipa',
      'bundleId': 'ly.demo',
      'appleAppId': '1234567890',
      'version': version,
      'auth': {'type': 'apiKey', 'keySecret': 'credential.default.asc_key'},
    },
  ),
  StepPlan(
    kind: 'upload.play',
    sideEffect: true,
    input: {
      'artifactName': 'default-$version.aab',
      'packageName': 'ly.demo',
      'version': version,
      'serviceAccountSecret': 'credential.default.play_sa',
    },
  ),
];

/// An engine with one project and a token of every kind, to ask the release
/// endpoints as each of them.
class ReleaseClient {
  new _(this.engine, this.projectId, this.workflowId, this.secrets);

  /// Starts an engine whose gates ask its approvals.
  static Future<ReleaseClient> start() async {
    final engine = await TestEngine.start(realApprovals: true);
    // A Shorebird app, so that its patches can be promoted (U7b).
    final workflows = await WorkflowClient.add(
      engine,
      files: {...projectFiles, 'shorebird.yaml': 'app_id: sb-demo\n'},
    );
    final workflowId = await workflows.create('ship', releaseWorkflow);
    final secrets = <DeviceTokenKind, String>{
      DeviceTokenKind.app: engine.secret,
      for (final kind in [
        DeviceTokenKind.cli,
        DeviceTokenKind.mcp,
        DeviceTokenKind.runner,
      ])
        kind: (await engine.tokens.issue(
          name: '${kind.name} token',
          kind: kind,
        )).secret,
    };
    return ReleaseClient._(engine, workflows.projectId, workflowId, secrets);
  }

  final TestEngine engine;
  final String projectId;

  /// The workflow the releases were made by.
  final String workflowId;

  /// The bearer secret of a token of each kind.
  final Map<DeviceTokenKind, String> secrets;

  /// Sends a request as a token of [kind].
  Future<RawResponse> send(
    String method,
    String path, {
    DeviceTokenKind kind = DeviceTokenKind.app,
    Object? body,
    String? rawBody,
  }) => engine.request(
    path,
    method: method,
    token: secrets[kind],
    body: rawBody ?? (body == null ? null : jsonEncode(body)),
  );

  /// Dispatches nothing: makes a draft release of the project's only flavor
  /// as the dispatch of a production release would, and returns its id.
  Future<String> open({
    String version = '1.2.0',
    int build = 5,
    String runId = 'run_1',
    List<StepPlan>? steps,
  }) async {
    await engine.runRepository.create(
      RunRecord(
        id: runId,
        projectId: projectId,
        workflowId: workflowId,
        workflowVersionId: 'wfv_x',
        sha: 'a' * 40,
        locksProject: false,
        request: const DispatchRequest(flavors: ['default']).toJson(),
        createdAt: engine.clock.now(),
      ),
    );
    final ids = await engine.releaseService.open(
      ReleaseOpening(
        projectId: projectId,
        appPath: '.',
        runId: runId,
        version: version,
        build: build,
        baseBranch: 'main',
        storeCountry: 'us',
        flavors: [
          FlavorSteps(flavor: 'default', steps: steps ?? uploadPlans()),
        ],
      ),
    );
    return ids['default']!;
  }

  var _jobs = 0;

  /// Records the jobs of a finished build of [releaseId]: both uploads, the
  /// branch, the tag and the pull request.
  Future<void> finishBuild(String releaseId, {String runId = 'run_1'}) async {
    Future<void> job(List<(String, Map<String, dynamic>?)> steps) async {
      final id = 'job_r${++_jobs}';
      await engine.jobRepository.create(
        JobRecord(
          id: id,
          workflowVersionId: 'wfv_x',
          projectId: projectId,
          releaseId: releaseId,
          runId: runId,
          state: JobState.succeeded,
          createdAt: engine.clock.now(),
        ),
        [
          for (final (ordinal, (kind, result)) in steps.indexed)
            StepRecord(
              jobId: id,
              ordinal: ordinal,
              kind: kind,
              sideEffect: true,
              input: const {},
              state: StepState.succeeded,
              result: result,
            ),
        ],
      );
    }

    await job([
      ('git.releaseBranch', {'name': 'release/1.2.0', 'outcome': 'created'}),
    ]);
    await job([('upload.appStore', const {})]);
    await job([('upload.play', const {})]);
    await job([
      ('git.tag', {'name': 'v1.2.0+5', 'sha': 'b' * 40, 'reused': false}),
      (
        'github.createPr',
        {
          'number': 7,
          'url': 'https://github.com/octo/app/pull/7',
          'headSha': 'b' * 40,
          'reused': false,
        },
      ),
    ]);
  }

  /// Makes a release that is uploaded, with its pull request.
  Future<String> uploaded() async {
    final id = await open();
    await finishBuild(id);
    await engine.releaseService.sync(id);
    return id;
  }

  /// The release [id] as the API shows it.
  Future<Release> read(String id) async =>
      Release.fromJson((await send('GET', '/releases/$id')).json);

  /// The events logged so far.
  Future<List<EngineEvent>> logged() async {
    final seen = <EngineEvent>[];
    final subscription = engine.events
        .subscribe(after: 0)
        .listen((entry) => seen.add(entry.event));
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();
    return seen;
  }

  Future<void> close() => engine.close();
}

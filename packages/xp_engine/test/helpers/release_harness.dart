import 'dart:math';

import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import 'all_steps.dart';
import 'approval_harness.dart';
import 'workflow_fixtures.dart';

/// A [JobControl] that cancels in the job repository and remembers it.
class RecordingControl implements JobControl {
  new(this.jobs, this.clock);

  final InMemoryJobRepository jobs;
  final ManualClock clock;

  /// The jobs cancelled, oldest first.
  final cancelled = <String>[];

  @override
  Future<Job> cancel(String id) async {
    cancelled.add(id);
    final job = (await jobs.get(id))!;
    await jobs.updateJob(
      job.copyWith(state: JobState.cancelled, finishedAt: clock.now()),
    );
    return toJob((await jobs.get(id))!, await jobs.steps(id));
  }

  @override
  Future<Job> get(String id) => throw UnimplementedError();

  @override
  Future<Job> resume(String id, {int? fromStep}) => throw UnimplementedError();
}

/// The upload steps of a flavor that goes to both stores.
List<StepPlan> uploadPlans({
  String version = '1.2.0+5',
  String track = 'internal',
}) => [
  StepPlan(
    kind: 'upload.appStore',
    sideEffect: true,
    input: {
      'artifactName': 'prod-$version.ipa',
      'bundleId': 'ly.demo',
      'appleAppId': '1234567890',
      'version': version,
      'auth': {'type': 'apiKey', 'keySecret': 'credential.prod.asc_key'},
    },
  ),
  StepPlan(
    kind: 'upload.play',
    sideEffect: true,
    input: {
      'artifactName': 'prod-$version.aab',
      'packageName': 'ly.demo',
      'version': version,
      'serviceAccountSecret': 'credential.prod.play_sa',
      'track': track,
    },
  ),
];

/// A [ReleaseService] over fakes, with the jobs of a release made by hand.
class ReleaseHarness {
  new _({
    required this.service,
    required this.releases,
    required this.jobs,
    required this.runs,
    required this.control,
    required this.events,
    required this.clock,
    required this.apple,
    required this.play,
    required this.dispatched,
    required this.workflows,
  });

  static Future<ReleaseHarness> create({
    bool withPlay = true,
    ReleaseRepository? repository,
  }) async {
    final clock = ManualClock(DateTime.utc(2026, 10, 14, 9));
    final releases = repository ?? InMemoryReleaseRepository();
    final jobs = InMemoryJobRepository();
    final runs = InMemoryRunRepository();
    final events = InMemoryEventLog(clock: clock);
    final projects = InMemoryProjectRepository();
    await projects.add(demoProject());
    final control = RecordingControl(jobs, clock);
    final workflows = WorkflowService(
      repository: InMemoryWorkflowRepository(),
      projects: projects,
      catalog: StepPlanners(allSteps()),
      events: events,
      clock: clock,
      random: Random(1),
    );
    final apple = FakeStoreStatusSource(ReleaseStore.apple);
    final play = FakeStoreStatusSource(ReleaseStore.play);
    final dispatched =
        <({String project, String workflow, DispatchRequest request})>[];
    late final ReleaseService service;
    service = ReleaseService(
      releases: releases,
      jobs: jobs,
      runRecords: runs,
      runs: RunService(runs: runs, jobs: jobs, control: control),
      workflows: workflows,
      poller: ReleaseStatusPoller(
        sources: [apple, if (withPlay) play],
        clock: clock,
      ),
      events: events,
      clock: clock,
      dispatch: (project, workflow, request) async {
        dispatched.add((
          project: project,
          workflow: workflow,
          request: request,
        ));
        // What the dispatcher does: it attaches the run to the release.
        final runId = 'run_${dispatched.length + 1}';
        final merge = request.release != null && request.version == null;
        await service.attach(
          releaseId: request.release!,
          projectId: project,
          kind: merge ? ReleaseRunKind.merge : ReleaseRunKind.build,
          runId: runId,
          build: merge ? null : 6,
        );
        await runs.create(
          RunRecord(
            id: runId,
            projectId: project,
            workflowId: workflow,
            workflowVersionId: 'wfv_x',
            sha: 'a' * 40,
            locksProject: false,
            createdAt: clock.now(),
          ),
        );
        return RunRecord(
          id: runId,
          projectId: project,
          workflowId: workflow,
          workflowVersionId: 'wfv_x',
          sha: 'a' * 40,
          locksProject: false,
          createdAt: clock.now(),
        ).toRun(const []);
      },
      random: Random(3),
    );
    return ReleaseHarness._(
      service: service,
      releases: releases,
      jobs: jobs,
      runs: runs,
      control: control,
      events: events,
      clock: clock,
      apple: apple,
      play: play,
      dispatched: dispatched,
      workflows: workflows,
    );
  }

  final ReleaseService service;
  final ReleaseRepository releases;
  final InMemoryJobRepository jobs;
  final InMemoryRunRepository runs;
  final RecordingControl control;
  final InMemoryEventLog events;
  final ManualClock clock;
  final FakeStoreStatusSource apple;
  final FakeStoreStatusSource play;
  final WorkflowService workflows;

  /// What the service dispatched, oldest first.
  final List<({String project, String workflow, DispatchRequest request})>
  dispatched;

  var _jobs = 0;

  /// Opens a release of the demo app's prod flavor and records its run as the
  /// first run of the release. Returns its id.
  Future<String> open({
    List<StepPlan>? steps,
    String version = '1.2.0',
    int build = 5,
    String runId = 'run_1',
    String flavor = 'prod',
  }) async {
    await runs.create(
      RunRecord(
        id: runId,
        projectId: 'prj_1',
        workflowId: 'wf_release',
        workflowVersionId: 'wfv_1',
        sha: 'a' * 40,
        locksProject: true,
        request: const DispatchRequest(
          flavors: ['prod'],
          platforms: ['android', 'ios'],
          inputs: {'notes': 'hello'},
        ).toJson(),
        createdAt: clock.now(),
      ),
    );
    final ids = await service.open(
      ReleaseOpening(
        projectId: 'prj_1',
        appPath: '.',
        runId: runId,
        version: version,
        build: build,
        baseBranch: 'main',
        storeCountry: 'us',
        flavors: [FlavorSteps(flavor: flavor, steps: steps ?? uploadPlans())],
      ),
    );
    return ids[flavor]!;
  }

  /// Adds a job of [releaseId] to the run [runId] with steps in the given
  /// states (`kind`, `state`, `result`).
  Future<String> addJob(
    String releaseId,
    List<(String, StepState, Map<String, dynamic>?)> steps, {
    String runId = 'run_1',
    JobState state = JobState.running,
    int stage = 0,
    String? message,
  }) async {
    final id = 'job_${++_jobs}';
    await jobs.create(
      JobRecord(
        id: id,
        workflowVersionId: 'wfv_1',
        projectId: 'prj_1',
        releaseId: releaseId,
        runId: runId,
        stage: stage,
        name: 'Job $id',
        state: state,
        message: message,
        createdAt: clock.now(),
      ),
      [
        for (final (ordinal, (kind, stepState, result)) in steps.indexed)
          StepRecord(
            jobId: id,
            ordinal: ordinal,
            kind: kind,
            sideEffect: true,
            input: const {},
            state: stepState,
            result: result,
          ),
      ],
    );
    return id;
  }

  /// Replaces the state of a step of the job [jobId].
  Future<void> setStep(
    String jobId,
    int ordinal,
    StepState state, {
    Map<String, dynamic>? result,
  }) async {
    final step = (await jobs.steps(jobId))[ordinal];
    await jobs.updateStep(step.copyWith(state: state, result: result));
  }

  /// Marks both uploads of a build done, as the jobs of the prepare, build and
  /// finalize stages would leave them.
  Future<void> finishBuild(String releaseId, {String runId = 'run_1'}) async {
    await addJob(
      releaseId,
      [
        (
          'git.releaseBranch',
          StepState.succeeded,
          {'name': 'release/1.2.0', 'outcome': 'created'},
        ),
      ],
      runId: runId,
      state: JobState.succeeded,
    );
    await addJob(
      releaseId,
      [
        ('build.ios', StepState.succeeded, null),
        ('upload.appStore', StepState.succeeded, {}),
      ],
      runId: runId,
      state: JobState.succeeded,
      stage: 1,
    );
    await addJob(
      releaseId,
      [
        ('build.android', StepState.succeeded, null),
        ('upload.play', StepState.succeeded, {}),
      ],
      runId: runId,
      state: JobState.succeeded,
      stage: 1,
    );
    await addJob(
      releaseId,
      [
        (
          'git.tag',
          StepState.succeeded,
          {'name': 'v1.2.0+5', 'sha': 'b' * 40, 'reused': false},
        ),
        ('git.push', StepState.succeeded, {}),
        (
          'github.createPr',
          StepState.succeeded,
          {
            'number': 7,
            'url': 'https://github.com/octo/demo/pull/7',
            'headSha': 'b' * 40,
            'reused': false,
          },
        ),
      ],
      runId: runId,
      state: JobState.succeeded,
      stage: 2,
    );
  }

  /// The release as stored.
  Future<ReleaseRecord> record(String id) async => (await releases.get(id))!;

  /// The events logged so far.
  Future<List<EngineEvent>> logged() async {
    final seen = <EngineEvent>[];
    final subscription = events
        .subscribe(after: 0)
        .listen((entry) => seen.add(entry.event));
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();
    return seen;
  }

  /// The release events logged so far.
  Future<List<EngineEvent>> releaseEvents() async => [
    for (final event in await logged())
      if (event.type.startsWith('release.')) event,
  ];
}

/// An `app` token for tests.
DeviceToken owner() => tokenOf(DeviceTokenKind.app);

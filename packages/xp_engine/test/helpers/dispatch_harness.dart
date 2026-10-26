import 'dart:math';

import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import 'all_steps.dart';
import 'job_harness.dart';
import 'scripted_git.dart';
import 'workflow_fixtures.dart';

/// A [ReleaseOpener] that remembers what a dispatch told it.
class FakeReleaseOpener implements ReleaseOpener {
  /// What each [open] was told, oldest first.
  final openings = <ReleaseOpening>[];

  /// What each [attach] was told, as `release project kind run build`.
  final attached = <String>[];

  /// The id the release of each flavor gets: `rel_<flavor>`.
  @override
  Future<Map<String, String>> open(ReleaseOpening opening) async {
    openings.add(opening);
    return {
      for (final flavor in opening.flavors)
        flavor.flavor: 'rel_${flavor.flavor}',
    };
  }

  /// Set to make the next [attach] fail with it.
  ReleaseException? attachFailure;

  @override
  Future<void> attach({
    required String releaseId,
    required String projectId,
    required ReleaseRunKind kind,
    required String runId,
    int? build,
  }) async {
    attached.add('$releaseId $projectId ${kind.name} $runId $build');
    final error = attachFailure;
    if (error != null) {
      attachFailure = null;
      throw error;
    }
  }

  /// The release a patch of each flavor applies to, by flavor.
  final patchables = <String, String>{};

  @override
  Future<String?> patchable({
    required String projectId,
    required String appPath,
    required String flavor,
    required AppVersion version,
  }) async => patchables[flavor];
}

/// The commit `main` resolves to.
const mainSha = 'a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1';

/// A dispatcher over fakes: a project with the demo app, a mirror that holds
/// `main`, and a scheduler without runners, so the jobs it makes stay queued
/// and can be looked at.
class DispatchHarness {
  new _({
    required this.git,
    required this.projects,
    required this.credentials,
    required this.counters,
    required this.stores,
    required this.jobs,
    required this.runs,
    required this.scheduler,
    required this.workflows,
    required this.planners,
    required this.dispatcher,
    required this.events,
    required this.pubspec,
    required this.workflowRepository,
  });

  static Future<DispatchHarness> create({
    List<AppProfile> apps = const [demoApp],
    String pubspecVersion = '1.2.3+45',
    List<SchedulerRunner> runners = const [],
    JobRepository? jobRepository,
    bool seeded = true,
    ReleaseOpener? releases,
    GateConfigRepository? gates,
    bool linuxIosBuilds = false,
  }) async {
    final git = ScriptedGit()..refs['main'] = mainSha;
    final projects = InMemoryProjectRepository();
    await projects.add(demoProject(apps: apps));
    final credentials = InMemoryCredentialRepository([
      demoFlavor('dev'),
      demoFlavor('prod'),
    ]);
    final counters = InMemoryBuildCounterRepository([('prj_1', '.')]);
    final stores = FakeStoreBuildNumbers();
    final jobs = JobHarness.create(repository: jobRepository);
    final runs = InMemoryRunRepository();
    final clock = ManualClock(DateTime.utc(2026, 10, 13, 9));
    final events = InMemoryEventLog(clock: clock);
    final registry = allSteps(git: git, jobs: jobs.jobs);
    final planners = StepPlanners(registry, linuxIosBuilds: linuxIosBuilds);
    final scheduler = Scheduler(
      runner: jobs.runner,
      records: jobs.jobs,
      runs: runs,
      events: events,
      runners: runners,
    );
    final workflowRepository = InMemoryWorkflowRepository();
    final workflows = WorkflowService(
      repository: workflowRepository,
      projects: projects,
      catalog: planners,
      events: events,
      clock: clock,
      random: Random(1),
    );
    final pubspec = InMemoryWorkspace({
      'pubspec.yaml': 'name: demo\nversion: $pubspecVersion\n',
    });
    final dispatcher = WorkflowDispatcher(
      workflows: workflows,
      planners: planners,
      projects: projects,
      credentials: credentials,
      models: InMemoryReleaseModelRepository(['prj_1']),
      git: git,
      allocator: BuildNumberAllocator(
        counters: counters,
        stores: stores,
        git: git,
      ),
      jobs: jobs.runner,
      records: jobs.jobs,
      runs: runs,
      scheduler: scheduler,
      events: events,
      clock: clock,
      workspaces: (_) => pubspec,
      worktreeAt: ScriptedGit.pathOf,
      releases: releases,
      gates: gates,
      random: seeded ? Random(2) : null,
    );
    return ._(
      git: git,
      projects: projects,
      credentials: credentials,
      counters: counters,
      stores: stores,
      jobs: jobs,
      runs: runs,
      scheduler: scheduler,
      workflows: workflows,
      planners: planners,
      dispatcher: dispatcher,
      events: events,
      pubspec: pubspec,
      workflowRepository: workflowRepository,
    );
  }

  final ScriptedGit git;
  final InMemoryProjectRepository projects;
  final InMemoryCredentialRepository credentials;
  final InMemoryBuildCounterRepository counters;
  final FakeStoreBuildNumbers stores;
  final JobHarness jobs;
  final InMemoryRunRepository runs;
  final Scheduler scheduler;
  final WorkflowService workflows;
  final StepPlanners planners;
  final WorkflowDispatcher dispatcher;
  final InMemoryEventLog events;

  /// Where the workflows are stored.
  final InMemoryWorkflowRepository workflowRepository;

  var _customs = 0;

  /// The workspace the version of the app is read from.
  final InMemoryWorkspace pubspec;

  /// Saves a credential of [kind] for the demo flavor [flavor].
  Future<void> saveCredential(
    String flavor,
    CredentialKind kind, {
    String? account,
  }) => credentials.put(
    demoCredential(demoFlavor(flavor), kind, account: account),
  );

  /// The id of the built-in workflow [name].
  Future<String> builtin(String name) async =>
      (await workflows.list('prj_1'))
          .firstWhere((workflow) => workflow.name == name)
          .id;

  /// Creates a workflow of the owner from [yaml] and returns its id.
  Future<String> custom(String yaml, {String? name}) async =>
      (await workflows.create(
        'prj_1',
        name: name ?? 'custom-${++_customs}',
        yaml: yaml,
      )).id;

  /// Dispatches the built-in workflow [name].
  Future<Run> dispatchBuiltin(
    String name, [
    DispatchRequest request = const DispatchRequest(),
  ]) async {
    final id = await builtin(name);
    return await dispatcher.dispatch('prj_1', id, request);
  }

  /// Plans dispatching the built-in workflow [name] without starting it.
  Future<DispatchPlan> planBuiltin(
    String name, [
    DispatchRequest request = const DispatchRequest(),
  ]) async => await dispatcher.plan('prj_1', await builtin(name), request);

  /// Dispatches [yaml] as a workflow of the owner.
  Future<Run> dispatchCustom(
    String yaml, [
    DispatchRequest request = const DispatchRequest(),
  ]) async {
    final id = await custom(yaml);
    return await dispatcher.dispatch('prj_1', id, request);
  }

  /// The job [id] with its steps.
  Future<Job> job(String id) => jobs.runner.get(id);

  /// The jobs of [run], with their steps, by stage.
  Future<List<Job>> jobsOf(Run run) async => [
    for (final job in run.jobs) await this.job(job.id),
  ];

  /// The kinds of the steps of [job].
  List<String> kinds(Job job) => [for (final step in job.steps) step.kind];

  /// The stored input of the [nth] step of [kind] in [job].
  Future<Map<String, dynamic>> input(
    Job job,
    String kind, {
    int nth = 0,
  }) async {
    final steps = await jobs.jobs.steps(job.id);
    return steps.where((step) => step.kind == kind).elementAt(nth).input;
  }
}

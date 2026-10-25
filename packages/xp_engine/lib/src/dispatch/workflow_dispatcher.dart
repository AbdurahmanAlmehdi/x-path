import 'dart:math';

import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/approvals/gate_config.dart';
import 'package:xp_engine/src/clock/clock.dart';
import 'package:xp_engine/src/credentials/credential_repository.dart';
import 'package:xp_engine/src/dispatch/ios_linux_limits.dart';
import 'package:xp_engine/src/dispatch/plan_context.dart';
import 'package:xp_engine/src/dispatch/skip_reason.dart';
import 'package:xp_engine/src/dispatch/step_planners.dart';
import 'package:xp_engine/src/git/git_exceptions.dart';
import 'package:xp_engine/src/git/git_models.dart';
import 'package:xp_engine/src/git/git_service.dart';
import 'package:xp_engine/src/jobs/job_repository.dart';
import 'package:xp_engine/src/jobs/job_runner.dart';
import 'package:xp_engine/src/projects/project_record.dart';
import 'package:xp_engine/src/projects/project_repository.dart';
import 'package:xp_engine/src/releases/release_exceptions.dart';
import 'package:xp_engine/src/releases/release_opener.dart';
import 'package:xp_engine/src/repositories/event_log.dart';
import 'package:xp_engine/src/runners/remote_step_policy.dart';
import 'package:xp_engine/src/scan/scan_source.dart';
import 'package:xp_engine/src/scheduler/capability.dart';
import 'package:xp_engine/src/scheduler/run_record.dart';
import 'package:xp_engine/src/scheduler/scheduler.dart';
import 'package:xp_engine/src/steps/step.dart';
import 'package:xp_engine/src/versioning/app_version.dart';
import 'package:xp_engine/src/versioning/build_number_allocator.dart';
import 'package:xp_engine/src/versioning/release_model.dart';
import 'package:xp_engine/src/versioning/release_model_repository.dart';
import 'package:xp_engine/src/versioning/release_worktree.dart';
import 'package:xp_engine/src/versioning/version_files.dart';
import 'package:xp_engine/src/versioning/versioning_exceptions.dart';
import 'package:xp_engine/src/versioning/workspace.dart';
import 'package:xp_engine/src/workflows/expression.dart';
import 'package:xp_engine/src/workflows/gate_action.dart';
import 'package:xp_engine/src/workflows/workflow_definition.dart';
import 'package:xp_engine/src/workflows/workflow_exceptions.dart';
import 'package:xp_engine/src/workflows/workflow_matrix.dart';
import 'package:xp_engine/src/workflows/workflow_parser.dart';
import 'package:xp_engine/src/workflows/workflow_service.dart';

/// The step types that have nothing to do with the version of the app: a
/// workflow with only these needs to know none.
const _unversionedKinds = {
  'analyze',
  'command',
  'git.checkout',
  'github.mergePr',
  'guard',
  'test',
};

/// Dispatches a workflow: turns it into a run with its jobs (D-11, D-19).
///
/// A dispatch
///
/// 1. reads the newest version of the workflow and checks it,
/// 2. fetches the project's mirror and resolves the ref to a commit,
/// 3. works out the version, and allocates the build number once for the run
///    (never handed back, even if the run fails),
/// 4. expands the matrix of each job into jobs, drops the cells whose `if` is
///    false, and plans every step of every job: the stored input of each step
///    comes from the workflow's `with` values and what the dispatch decided,
/// 5. makes the release of each flavor of a workflow that cuts a release
///    branch, or attaches the run to the release the request names (a new
///    build of it, or the merge of its pull request), and
/// 6. creates the run and its jobs, all `queued`, and wakes the [Scheduler].
///
/// The plan is complete before anything is stored, so a dispatch that cannot
/// work (an unknown flavor, a credential that is missing) leaves nothing
/// behind but the build number it allocated. [plan] makes the same plan and
/// stores nothing, not even the build number (a dry run). A job gets
/// no worktree here: its first step, `git.checkout`, makes it when the job
/// runs.
class WorkflowDispatcher {
  /// Creates the dispatcher.
  ///
  /// [random] is for tests; it must be cryptographically secure otherwise.
  new({
    required this._workflows,
    required this._planners,
    required this._projects,
    required this._credentials,
    required this._models,
    required this._git,
    required this._allocator,
    required this._jobs,
    required this._records,
    required this._runs,
    required this._scheduler,
    required this._events,
    required this._clock,
    required this._workspaces,
    required this._worktreeAt,
    this._releases,
    this._gates,
    Random? random,
  }) : _random = random ?? Random.secure();

  final WorkflowService _workflows;
  final StepPlanners _planners;
  final ProjectRepository _projects;
  final CredentialRepository _credentials;
  final ReleaseModelRepository _models;
  final GitService _git;
  final BuildNumberAllocator _allocator;
  final JobRunner _jobs;
  final JobRepository _records;
  final RunRepository _runs;
  final Scheduler _scheduler;
  final EventLog _events;
  final Clock _clock;
  final WorkspaceOpener _workspaces;
  final WorktreeLocator _worktreeAt;
  final ReleaseOpener? _releases;

  /// The gates of the projects, for the gates a [plan] names; every gate is
  /// on without it.
  final GateConfigRepository? _gates;
  final Random _random;

  /// The version in the pubspec of an app at a commit, by (commit, app
  /// path): a commit never changes, so a preview reads it once.
  final _versions = <(String, String), AppVersion>{};

  /// Dispatches the workflow [workflowId] of the project [projectId].
  ///
  /// Throws a `ProjectNotFoundException`, a [WorkflowNotFoundException], a
  /// [WorkflowInvalidException] when the document no longer is valid, a
  /// [DispatchException] when the request asks for something the project
  /// cannot do (a GitHub step on a project that is not on GitHub, ADR 0015),
  /// and a `GitException` or `GitHub` failure when the mirror
  /// cannot be fetched.
  ///
  /// With [versionId] it runs that version of the workflow, not the newest.
  Future<Run> dispatch(
    String projectId,
    String workflowId,
    DispatchRequest request, {
    String? versionId,
  }) async {
    final (:stored, :definition, :context, :kinds) = await _prepare(
      projectId,
      workflowId,
      request,
      dryRun: false,
      versionId: versionId,
    );
    final runId = context.runId;
    final sha = context.sha;
    final ref = context.ref;
    final name = context.version?.name;
    final build = context.build;
    final flavors = context.flavors;
    final platforms = context.platforms;
    final jobs = await _planJobs(definition, context);
    if (jobs.isEmpty) {
      throw DispatchException(
        'Nothing to run: no job is left for the flavors '
        '(${flavors.map((flavor) => flavor.name).join(', ')}) and the '
        'platforms (${platforms.join(', ')}) of this dispatch.',
      );
    }
    for (final job in jobs) {
      if (job.narrowed.isNotEmpty && !await _scheduler.couldRun(job.narrowed)) {
        throw DispatchException(
          '${job.name} needs ${job.narrowed.map((n) => n.described).join(', ')}'
          ', which no paired runner offers: ${job.narrowing.join('; ')}.',
        );
      }
    }

    final releaseOf = await _linkReleases(request, kinds, context, jobs);

    final run = RunRecord(
      id: runId,
      projectId: projectId,
      workflowId: workflowId,
      workflowVersionId: stored.version.id,
      sha: sha,
      ref: ref,
      locksProject: definition.locksProject,
      version: name == null ? null : '$name',
      build: build,
      request: request.toJson(),
      createdAt: _clock.now(),
    );
    await _runs.create(run);
    final created = <String>[];
    try {
      for (final job in jobs) {
        await _jobs.create(
          id: job.id,
          workflowVersionId: stored.version.id,
          projectId: projectId,
          releaseId: releaseOf[job.id],
          sha: sha,
          runId: runId,
          stage: job.stage,
          name: job.name,
          capabilities: job.capabilities,
          narrowing: job.narrowing,
          steps: job.steps,
        );
        created.add(job.id);
      }
    } on Object {
      for (final id in created) {
        await _jobs.cancel(id);
      }
      rethrow;
    }
    _events.append(
      RunDispatched(
        runId: runId,
        projectId: projectId,
        workflowId: workflowId,
        jobIds: created,
      ),
    );
    await _scheduler.pump();
    return run.toRun(await _records.forRun(runId));
  }

  /// Plans dispatching the workflow [workflowId] of [projectId] with
  /// [request] and starts nothing (a dry run): the jobs it would
  /// make and where each would run, the jobs it leaves out and why (a job
  /// it cannot plan is left out too, and [DispatchPlan.blocked] says that a
  /// dispatch would be refused), the gates, and the version and build number
  /// it would take. No build number is taken, no release is opened.
  ///
  /// Throws what [dispatch] throws for a request it cannot plan at all.
  Future<DispatchPlan> plan(
    String projectId,
    String workflowId,
    DispatchRequest request,
  ) async {
    final (:stored, :definition, :context, :kinds) = await _prepare(
      projectId,
      workflowId,
      request,
      dryRun: true,
    );
    final skipped = <SkippedJob>[];
    final jobs = await _planJobs(definition, context, skipped: skipped);
    final gates = await _gates?.get(projectId) ?? const GateConfig();
    return DispatchPlan(
      flavors: [for (final flavor in context.flavors) flavor.name],
      platforms: context.platforms,
      currentVersion: context.current?.toString(),
      version: context.version?.name.toString(),
      build: context.build,
      releaseVersion: context.releaseVersion?.toString(),
      stages: [
        for (final (index, stage) in definition.stages.indexed)
          if (jobs.where((job) => job.stage == index).toList()
              case final planned when planned.isNotEmpty)
            PlannedStage(
              name: stage.name,
              jobs: [for (final job in planned) await _plannedJob(job)],
              gates: {
                for (final job in planned)
                  for (final step in job.steps)
                    if (step.kind == 'gate')
                      if (GateAction.fromWire('${step.input['action']}')
                          case final action? when gates.isGated(action))
                        action.wire,
              }.toList(),
            ),
      ],
      skipped: skipped,
    );
  }

  Future<PlannedJob> _plannedJob(_PlannedJob job) async {
    final kinds = [for (final step in job.steps) step.kind];
    final placement = await _scheduler.placement(job.capabilities, kinds);
    return PlannedJob(
      name: job.name,
      flavor: job.cell['flavor'],
      platform: job.cell['platform'],
      capabilities: job.capabilities,
      engineOnly: !RemoteStepPolicy.canRunRemotely(kinds),
      local: placement.local,
      runner: placement.runner,
      waitReason: placement.waitReason,
    );
  }

  /// Dispatches the run [runId] again: a new run of the same version of the
  /// workflow, at the same commit, with the same request (inputs, flavors,
  /// platforms, bump). It gets a build number of its own.
  ///
  /// Throws a [RunNotFoundException], and what [dispatch] throws.
  Future<Run> again(String runId) async {
    final run = await _runs.get(runId) ?? (throw RunNotFoundException(runId));
    final asked = run.dispatchRequest ?? const DispatchRequest();
    return await dispatch(
      run.projectId,
      run.workflowId,
      DispatchRequest(
        ref: run.sha,
        app: asked.app,
        flavors: asked.flavors,
        platforms: asked.platforms,
        bump: asked.bump,
        version: asked.version,
        releaseVersion: asked.releaseVersion,
        release: asked.release,
        inputs: asked.inputs,
      ),
      versionId: run.workflowVersionId,
    );
  }

  /// What [dispatch] and [plan] work out before planning the jobs: the
  /// workflow, the request read against the project, the commit, the
  /// version and (outside a [dryRun]) the build number it allocates.
  Future<
    ({
      StoredWorkflow stored,
      WorkflowDefinition definition,
      RunContext context,
      Set<String> kinds,
    })
  >
  _prepare(
    String projectId,
    String workflowId,
    DispatchRequest request, {
    required bool dryRun,
    String? versionId,
  }) async {
    final stored = versionId == null
        ? await _workflows.latest(projectId, workflowId)
        : await _workflows.stored(projectId, workflowId, versionId);
    if (stored.workflow.archivedAt != null) {
      throw WorkflowArchivedException(stored.workflow.name);
    }
    final parsed = WorkflowParser(_planners).parse(stored.version.yaml);
    final definition = parsed.definition;
    if (definition == null) throw WorkflowInvalidException(parsed.issues);
    final project = (await _projects.get(projectId))!;
    final runId = _id('run');

    final app = _app(project, request.app);
    final flavors = _flavors(app, request.flavors, definition);
    final platforms = _platforms(app, request.platforms);
    final inputs = _inputs(definition, request);
    final steps = definition.jobs.expand((job) => job.steps).toList();
    final kinds = {for (final step in steps) step.kind};
    _refuseGitHubSteps(project, stored.workflow.name, kinds);

    final mirror = await _git.ensureMirror(
      key: project.sourceKey,
      remoteUrl: project.remote,
    );
    final ref = request.ref ?? project.defaultBaseBranch;
    final sha = await _commitOf(mirror, ref, dryRun: dryRun);
    final model = await _models.get(projectId);
    final scope = TagScope(app: app.name);

    final releaseVersion = _releaseVersion(request, kinds, definition, inputs);
    final current = kinds.difference(_unversionedKinds).isEmpty
        ? null
        : await _currentVersion(mirror, sha, app, runId);
    VersionName? name;
    int? build;
    if (kinds.contains('version.bump')) {
      name = _versionName(request, current);
      final allocate = dryRun ? _allocator.peek : _allocator.allocate;
      build = await allocate(
        projectId: projectId,
        appPath: app.path,
        mirror: mirror,
        model: model,
        scope: scope,
        iosBundleId: flavors.firstOrNull?.iosBundleId,
        androidAppId: flavors.firstOrNull?.androidAppId,
      );
    }
    final patch = releaseVersion != null && kinds.contains('git.tag')
        ? await _nextPatch(mirror, model, scope, releaseVersion)
        : null;

    final context = RunContext(
      runId: runId,
      project: project,
      app: app,
      flavors: flavors,
      platforms: platforms,
      ref: ref,
      sha: sha,
      mirror: mirror,
      model: model,
      worktreeAt: _worktreeAt,
      inputs: inputs,
      bump: (request.bump ?? VersionBump.keep).wire,
      version: name == null ? null : AppVersion(name, build),
      build: build,
      current: current,
      releaseVersion: releaseVersion,
      patch: patch,
      release: request.release,
    );
    return (
      stored: stored,
      definition: definition,
      context: context,
      kinds: kinds,
    );
  }

  /// The commit [ref] names in [mirror], fetched first. A [dryRun] does not
  /// fetch: a preview runs as the owner types, so a ref the mirror does not
  /// know yet is reported, and the dispatch fetches it.
  Future<String> _commitOf(
    GitMirror mirror,
    String ref, {
    required bool dryRun,
  }) async {
    if (dryRun) {
      try {
        return await _git.resolveRef(mirror, ref);
      } on GitRefNotFoundException {
        throw DispatchException(
          'This engine has no "$ref" yet.',
          hint: 'Dispatching fetches it from the repository first.',
          details: {'reason': ErrorReason.refUnknown, 'ref': ref},
        );
      }
    }
    await _git.fetch(mirror);
    try {
      return await _git.resolveRef(mirror, ref);
    } on GitRefNotFoundException catch (error) {
      throw DispatchException(error.message);
    }
  }

  // -------------------------------------------------------------- releases

  /// Refuses a workflow with a step that needs GitHub on a [project] that is
  /// not on GitHub (Q3 of the runner plan, ADR 0015): `github.*` steps call
  /// the GitHub API, and `git.push` pushes with the GitHub token only.
  static void _refuseGitHubSteps(
    ProjectRecord project,
    String workflow,
    Set<String> kinds,
  ) {
    if (project.isOnGitHub) return;
    final step = kinds.where(stepNeedsGitHub).firstOrNull;
    if (step == null) return;
    final where = project.host == Project.localHost
        ? 'a local repository'
        : 'on ${project.host}';
    throw DispatchException(
      '${project.fullName} is $where, not on GitHub, so "$workflow" cannot '
      'run: its "$step" step works only on GitHub, where XPath pushes and '
      'opens pull requests with its GitHub token. Run a workflow without '
      'GitHub steps, such as dev-build or test, or keep a private mirror of '
      'the repository on GitHub and add that as the project.',
    );
  }

  /// The release of each job, by job id: the releases a workflow that cuts a
  /// release branch makes (one per flavor), or the release the request names.
  ///
  /// Throws a [DispatchException] if the request names a release that cannot
  /// take this run.
  Future<Map<String, String>> _linkReleases(
    DispatchRequest request,
    Set<String> kinds,
    RunContext context,
    List<_PlannedJob> jobs,
  ) async {
    final opener = _releases;
    final named = request.release;
    if (named != null) {
      if (opener == null) {
        throw const DispatchException('This engine does not track releases.');
      }
      final ReleaseRunKind kind;
      if (kinds.contains('github.mergePr')) {
        kind = ReleaseRunKind.merge;
      } else if (kinds.contains('version.bump')) {
        kind = ReleaseRunKind.build;
      } else {
        throw const DispatchException(
          'A run of a release has to build it again (a "version.bump" step) '
          'or merge its pull request (a "github.mergePr" step).',
        );
      }
      try {
        await opener.attach(
          releaseId: named,
          projectId: context.project.id,
          kind: kind,
          runId: context.runId,
          build: context.build,
        );
      } on ReleaseException catch (error) {
        throw DispatchException(error.message);
      }
      return {for (final job in jobs) job.id: named};
    }
    if (opener == null || !kinds.contains('git.releaseBranch')) {
      return const {};
    }
    // Planning a "git.releaseBranch" step needed a version, so there is one.
    final version = context.version!;
    final steps = <String, List<StepPlan>>{};
    for (final job in jobs) {
      final flavor = job.cell['flavor'];
      if (flavor != null) steps.putIfAbsent(flavor, () => []).addAll(job.steps);
    }
    final ids = await opener.open(
      ReleaseOpening(
        projectId: context.project.id,
        appPath: context.app.path,
        runId: context.runId,
        version: '${version.name}',
        build: version.build!,
        baseBranch: context.project.defaultBaseBranch,
        storeCountry: context.app.storeCountry,
        flavors: [
          for (final entry in steps.entries)
            FlavorSteps(flavor: entry.key, steps: entry.value),
        ],
      ),
    );
    return {for (final job in jobs) job.id: ?ids[job.cell['flavor']]};
  }

  // ----------------------------------------------------------- the request

  AppProfile _app(ProjectRecord project, String? path) {
    final apps = project.profile.apps;
    if (apps.isEmpty) {
      throw const DispatchException(
        'The project has no Flutter app; scan it again.',
      );
    }
    if (path == null) {
      if (apps.length == 1) return apps.single;
      throw DispatchException(
        'The project has several apps: give "app" (one of '
        '${apps.map((app) => app.path).join(', ')}).',
      );
    }
    return apps.where((app) => app.path == path).firstOrNull ??
        (throw DispatchException(
          'The project has no app at "$path" (it has '
          '${apps.map((app) => app.path).join(', ')}).',
        ));
  }

  List<FlavorProfile> _flavors(
    AppProfile app,
    List<String>? asked,
    WorkflowDefinition definition,
  ) {
    if (asked != null) {
      return [
        for (final name in asked)
          app.flavors.where((flavor) => flavor.name == name).firstOrNull ??
              (throw DispatchException(
                'The app has no flavor "$name" (it has '
                '${app.flavors.map((flavor) => flavor.name).join(', ')}).',
              )),
      ];
    }
    if (app.flavors.length == 1) return app.flavors;
    final chosen = [
      for (final flavor in app.flavors)
        if (flavor.prod == definition.locksProject) flavor,
    ];
    if (chosen.isEmpty) {
      throw DispatchException(
        definition.locksProject
            ? 'No flavor of the app is a production flavor; give "flavors" or '
                  "mark one as production in the project's profile."
            : 'Every flavor of the app is a production flavor; give '
                  '"flavors".',
        details: const {'reason': ErrorReason.productionFlavor},
      );
    }
    return chosen;
  }

  List<String> _platforms(AppProfile app, List<String>? asked) {
    if (asked == null) {
      return [if (app.hasAndroid) 'android', if (app.hasIos) 'ios'];
    }
    for (final platform in asked) {
      if (!platformNames.contains(platform)) {
        throw DispatchException(
          'Unknown platform "$platform"; use ${platformNames.join(' or ')}.',
        );
      }
      if (platform == 'android' && !app.hasAndroid) {
        throw const DispatchException('The app has no Android project.');
      }
      if (platform == 'ios' && !app.hasIos) {
        throw const DispatchException('The app has no iOS project.');
      }
    }
    return asked.toSet().toList();
  }

  /// The values of the inputs of [definition]: what [request] gives, the
  /// dispatch's `releaseVersion` for a release input it leaves out, else
  /// the default. Each must be a value its input takes.
  Map<String, Object?> _inputs(
    WorkflowDefinition definition,
    DispatchRequest request,
  ) {
    final given = {
      for (final input in definition.inputs)
        if (input.type == InputType.release)
          input.name: ?request.releaseVersion,
      ...request.inputs,
    };
    final declared = {for (final input in definition.inputs) input.name: input};
    for (final name in given.keys) {
      if (!declared.containsKey(name)) {
        final has = declared.isEmpty
            ? '.'
            : ' (it has ${declared.keys.join(', ')}).';
        throw DispatchException('The workflow has no input "$name"$has');
      }
    }
    final values = {
      for (final input in declared.values)
        input.name: given.containsKey(input.name)
            ? given[input.name]
            : input.required
            ? throw DispatchException('The input "${input.name}" is needed.')
            : input.defaultValue,
    };
    for (final input in declared.values) {
      if (input.problemOf(values[input.name]) case final problem?) {
        throw DispatchException('The input "${input.name}" $problem.');
      }
    }
    return values;
  }

  /// The release a patch applies to: the dispatch's `releaseVersion`, else
  /// the value of the workflow's release input.
  AppVersion? _releaseVersion(
    DispatchRequest request,
    Set<String> kinds,
    WorkflowDefinition definition,
    Map<String, Object?> inputs,
  ) {
    final text =
        request.releaseVersion ??
        definition.inputs
            .where((input) => input.type == InputType.release)
            .map((input) => inputs[input.name])
            .whereType<String>()
            .firstOrNull;
    if (text == null) {
      if (kinds.contains('shorebird.patch')) {
        throw const DispatchException(
          'This workflow patches a release: give "releaseVersion", for '
          'example 5.4.1+3283.',
        );
      }
      return null;
    }
    try {
      final version = AppVersion.parse(text);
      if (version.build == null) {
        throw const DispatchException(
          '"releaseVersion" needs a build number, for example 5.4.1+3283.',
        );
      }
      return version;
    } on FormatException catch (error) {
      throw DispatchException(error.message);
    }
  }

  // --------------------------------------------------------------- version

  /// The version the pubspec of [app] has at [sha], read in a worktree that
  /// lives as long as the read.
  Future<AppVersion> _currentVersion(
    GitMirror mirror,
    String sha,
    AppProfile app,
    String runId,
  ) async {
    final key = (sha, app.path);
    if (_versions[key] case final known?) return known;
    final worktree = await _git.createWorktree(
      mirror,
      name: 'dispatch-$runId',
      sha: sha,
    );
    try {
      final state = await VersionFiles(_workspaces(worktree.path))
          .read([joinScanPath(app.path, 'pubspec.yaml')]);
      if (_versions.length >= 64) _versions.remove(_versions.keys.first);
      return _versions[key] = state.pubspec;
    } on VersionFileException catch (error) {
      throw DispatchException('${error.path}: ${error.message}');
    } finally {
      await _git.removeWorktree(worktree);
    }
  }

  VersionName _versionName(DispatchRequest request, AppVersion? current) {
    final asked = request.version;
    if (asked != null) {
      try {
        return VersionName.parse(asked);
      } on FormatException catch (error) {
        throw DispatchException(error.message);
      }
    }
    final from = current!.name;
    return switch (request.bump ?? VersionBump.keep) {
      VersionBump.major => VersionName(from.major + 1, 0, 0),
      VersionBump.minor => VersionName(from.major, from.minor + 1, 0),
      VersionBump.patch => VersionName(from.major, from.minor, from.patch + 1),
      VersionBump.keep => from,
    };
  }

  /// The number of the next patch of [release]: one more than the patch tags
  /// it has.
  Future<int> _nextPatch(
    GitMirror mirror,
    ReleaseModel model,
    TagScope scope,
    AppVersion release,
  ) async {
    var last = 0;
    for (final tag in await _git.listTags(mirror)) {
      final parsed = model.parseTag(tag.name, scope: scope);
      if (parsed != null &&
          parsed.isPatch &&
          parsed.version == release.name &&
          parsed.build == release.build &&
          parsed.patch! > last) {
        last = parsed.patch!;
      }
    }
    return last + 1;
  }

  // -------------------------------------------------------------- planning

  /// The jobs of [definition] in [run]: every cell of every matrix whose
  /// `if` holds. With [skipped] (a dry run) the cells left out are added to
  /// it with the reason, and so is a job that cannot be planned, which
  /// otherwise fails the dispatch.
  Future<List<_PlannedJob>> _planJobs(
    WorkflowDefinition definition,
    RunContext run, {
    List<SkippedJob>? skipped,
  }) async {
    final planned = <_PlannedJob>[];
    for (final (stage, stageDefinition) in definition.stages.indexed) {
      for (final job in stageDefinition.jobs) {
        for (final cell in expandMatrix(job, run.scope)) {
          final context = await _jobContext(job, cell, run, planned);
          SkippedJob skip(String reason, {bool blocks = false}) => SkippedJob(
            name: _jobName(job, cell, context.scope),
            stage: stageDefinition.name,
            flavor: cell['flavor'],
            platform: cell['platform'],
            reason: reason,
            blocks: blocks,
          );
          final condition = job.condition;
          if (condition != null &&
              !Expression.isTruthy(condition.evaluate(context.scope))) {
            skipped?.add(
              skip(
                skipReason(condition, context.scope, flavor: cell['flavor']),
              ),
            );
            continue;
          }
          if (skipped == null) {
            planned.add(await _planJob(job, cell, stage, context));
            continue;
          }
          try {
            planned.add(await _planJob(job, cell, stage, context));
          } on DispatchException catch (error) {
            skipped.add(skip(error.message, blocks: true));
          }
        }
      }
    }
    return planned;
  }

  Future<JobContext> _jobContext(
    JobDefinition definition,
    Map<String, String> cell,
    RunContext run,
    List<_PlannedJob> earlier,
  ) async {
    final id = _jobs.newJobId();
    final platform = cell['platform'];
    if (platform != null) {
      if (!platformNames.contains(platform)) {
        throw DispatchException(
          'Line ${definition.position.line}: unknown platform "$platform".',
        );
      }
      if ((platform == 'android' && !run.app.hasAndroid) ||
          (platform == 'ios' && !run.app.hasIos)) {
        throw DispatchException(
          'Line ${definition.position.line}: the app has no $platform '
          'project.',
        );
      }
    }
    final flavorName = cell['flavor'];
    final flavor = flavorName == null
        ? null
        : run.app.flavors.where((f) => f.name == flavorName).firstOrNull ??
              (throw DispatchException(
                'Line ${definition.position.line}: the app has no flavor '
                '"$flavorName".',
              ));
    final credentialFlavor = flavor == null
        ? null
        : await _credentials.findFlavor(
            run.project.id,
            run.app.path,
            flavor.name,
          );
    final credentials = credentialFlavor == null
        ? const <Never>[]
        : await _credentials.assignments(flavorId: credentialFlavor.id);
    final worktree = ReleaseWorktree(
      path: run.worktreeAt(run.mirror, id),
      mirror: run.mirror,
      sha: run.sha,
      appPath: run.app.path,
      versionFiles: flavor?.versionFiles ?? const [],
      releaseModel: run.model,
      scope: TagScope(app: run.app.name, flavor: flavor?.name),
    );
    return JobContext(
      run: run,
      jobId: id,
      worktree: worktree,
      platform: platform,
      flavor: flavor,
      flavorValue: flavor == null ? null : flavorScope(flavor, credentials),
      credentialFlavor: credentialFlavor,
      credentials: credentials,
      commitSources: _commitSources(cell, earlier),
    );
  }

  /// The jobs already planned that a `commitFrom` can name, by their id in
  /// the workflow: the one whose matrix cell agrees with this one on the axes
  /// they share.
  Map<String, String> _commitSources(
    Map<String, String> cell,
    List<_PlannedJob> earlier,
  ) {
    final sources = <String, String>{};
    for (final job in earlier) {
      final agrees = job.cell.entries.every(
        (entry) => cell[entry.key] == null || cell[entry.key] == entry.value,
      );
      if (agrees) sources.putIfAbsent(job.definitionId, () => job.id);
    }
    return sources;
  }

  Future<_PlannedJob> _planJob(
    JobDefinition definition,
    Map<String, String> cell,
    int stage,
    JobContext context,
  ) async {
    final scope = context.scope;
    final steps = <StepPlan>[];
    final needs = [
      for (final capability in definition.capabilities)
        CapabilityNeed([capability]),
    ];
    for (final step in definition.steps) {
      final condition = step.condition;
      if (condition != null &&
          !Expression.isTruthy(condition.evaluate(scope))) {
        continue;
      }
      final planning = StepPlanning(
        kind: step.kind,
        job: context,
        values: {
          for (final entry in step.withValues.entries)
            entry.key: _resolve(entry.value, scope),
        },
        position: step.position,
      );
      if (step.gate != null) {
        steps.add(
          _planners.gate(
            action: step.gate!,
            projectId: context.run.project.id,
            sha: context.run.sha,
            version: _gateVersion(context.run),
          ),
        );
      }
      steps.add(await _planners.plan(planning));
      needs.addAll(_planners.needsOf(planning));
    }
    final (:placed, :narrowed, :narrowing) = _narrow(
      needs,
      steps,
      context.run.app,
    );
    return _PlannedJob(
      id: context.jobId,
      definitionId: definition.id,
      cell: cell,
      stage: stage,
      name: _jobName(definition, cell, scope),
      capabilities: [for (final need in placed) need.wire]..sort(),
      narrowed: narrowed,
      narrowing: narrowing,
      steps: steps,
    );
  }

  /// What the job of [definition] in [cell] is called: its `name`, else its
  /// id and the cell.
  String _jobName(
    JobDefinition definition,
    Map<String, String> cell,
    Map<String, Object?> scope,
  ) {
    final name = definition.name?.evaluate(scope);
    if (name is String && name.isNotEmpty) return name;
    return '${definition.id}'
        '${cell.isEmpty ? '' : ' (${cell.values.join(', ')})'}';
  }

  /// [needs] without repeats, and without an any-of need that a need of one
  /// of its capabilities already meets.
  static List<CapabilityNeed> _simplified(List<CapabilityNeed> needs) {
    final single = {
      for (final need in needs)
        if (need.anyOf.length == 1) need.anyOf.single,
    };
    final kept = <CapabilityNeed>[];
    for (final need in needs) {
      if (kept.contains(need) ||
          (need.anyOf.length > 1 && need.anyOf.any(single.contains))) {
        continue;
      }
      kept.add(need);
    }
    return kept;
  }

  /// [needs], simplified, narrowed to `ios-sign` where Linux could build the
  /// iOS app but the job uses something Linux iOS builds lack (ADR 0014),
  /// with the needs it narrowed and why. A step that needs `ios-sign` itself
  /// (Shorebird iOS) still gives its reason.
  static ({
    List<CapabilityNeed> placed,
    List<CapabilityNeed> narrowed,
    List<String> narrowing,
  })
  _narrow(List<CapabilityNeed> needs, List<StepPlan> steps, AppProfile app) {
    bool linux(CapabilityNeed need) =>
        need.anyOf.length > 1 && need.anyOf.contains(Capability.iosLinux);
    final reasons = needs.any(linux)
        ? iosLinuxLimits(steps, app)
        : const <String>[];
    if (reasons.isEmpty) {
      return (
        placed: _simplified(needs),
        narrowed: const [],
        narrowing: const [],
      );
    }
    final narrowed = [
      for (final need in needs.where(linux))
        CapabilityNeed([
          for (final capability in need.anyOf)
            if (capability != Capability.iosLinux) capability,
        ]),
    ];
    return (
      placed: _simplified([
        ...needs.where((need) => !linux(need)),
        ...narrowed,
      ]),
      narrowed: narrowed,
      narrowing: reasons,
    );
  }

  /// What a gate binds an approval to besides the project, action and
  /// commit: the version released, or the patch.
  String? _gateVersion(RunContext run) {
    if (run.version != null) return '${run.version}';
    final release = run.releaseVersion;
    if (release == null) return null;
    return run.patch == null ? '$release' : '$release-p${run.patch}';
  }

  /// [value] with the placeholders in its strings replaced.
  Object? _resolve(Object? value, Map<String, Object?> scope) =>
      switch (value) {
        final String text when text.contains(r'${{') => Template.parse(
          text,
        ).evaluate(scope),
        final List<Object?> items => [
          for (final item in items) _resolve(item, scope),
        ],
        final Map<String, Object?> map => {
          for (final entry in map.entries)
            entry.key: _resolve(entry.value, scope),
        },
        _ => value,
      };

  String _id(String prefix) {
    final hex = List.generate(
      8,
      (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    );
    return '${prefix}_${hex.join()}';
  }
}

class _PlannedJob {
  const new({
    required this.id,
    required this.definitionId,
    required this.cell,
    required this.stage,
    required this.name,
    required this.capabilities,
    required this.narrowed,
    required this.narrowing,
    required this.steps,
  });

  final String id;
  final String definitionId;
  final Map<String, String> cell;
  final int stage;
  final String name;
  final List<String> capabilities;
  final List<CapabilityNeed> narrowed;
  final List<String> narrowing;
  final List<StepPlan> steps;
}

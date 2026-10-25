import 'dart:math';

import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/clock/clock.dart';
import 'package:xp_engine/src/credentials/credential_repository.dart';
import 'package:xp_engine/src/dispatch/ios_linux_limits.dart';
import 'package:xp_engine/src/dispatch/plan_context.dart';
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
/// behind but the build number it allocated. A job gets no worktree here: its
/// first step, `git.checkout`, makes it when the job runs.
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
  final Random _random;

  /// Dispatches the workflow [workflowId] of the project [projectId].
  ///
  /// Throws a `ProjectNotFoundException`, a [WorkflowNotFoundException], a
  /// [WorkflowInvalidException] when the document no longer is valid, a
  /// [DispatchException] when the request asks for something the project
  /// cannot do (a GitHub step on a project that is not on GitHub, ADR 0015),
  /// and a `GitException` or `GitHub` failure when the mirror
  /// cannot be fetched.
  Future<Run> dispatch(
    String projectId,
    String workflowId,
    DispatchRequest request,
  ) async {
    final stored = await _workflows.latest(projectId, workflowId);
    final parsed = WorkflowParser(_planners).parse(stored.version.yaml);
    final definition = parsed.definition;
    if (definition == null) throw WorkflowInvalidException(parsed.issues);
    final project = (await _projects.get(projectId))!;
    final runId = _id('run');

    final app = _app(project, request.app);
    final flavors = _flavors(app, request.flavors, definition);
    final platforms = _platforms(app, request.platforms);
    final inputs = _inputs(definition, request.inputs);
    final steps = definition.jobs.expand((job) => job.steps).toList();
    final kinds = {for (final step in steps) step.kind};
    _refuseGitHubSteps(project, stored.workflow.name, kinds);

    final mirror = await _git.ensureMirror(
      key: project.sourceKey,
      remoteUrl: project.remote,
    );
    await _git.fetch(mirror);
    final ref = request.ref ?? project.defaultBaseBranch;
    final String sha;
    try {
      sha = await _git.resolveRef(mirror, ref);
    } on GitRefNotFoundException catch (error) {
      throw DispatchException(error.message);
    }
    final model = await _models.get(projectId);
    final scope = TagScope(app: app.name);

    final releaseVersion = _releaseVersion(request, kinds);
    final current = kinds.difference(_unversionedKinds).isEmpty
        ? null
        : await _currentVersion(mirror, sha, app, runId);
    VersionName? name;
    int? build;
    if (kinds.contains('version.bump')) {
      name = _versionName(request, current);
      build = await _allocator.allocate(
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
                  'mark one with PATCH /projects/{id}.'
            : 'Every flavor of the app is a production flavor; give '
                  '"flavors".',
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

  Map<String, Object?> _inputs(
    WorkflowDefinition definition,
    Map<String, dynamic> given,
  ) {
    final declared = {for (final input in definition.inputs) input.name: input};
    for (final name in given.keys) {
      if (!declared.containsKey(name)) {
        final has = declared.isEmpty
            ? '.'
            : ' (it has ${declared.keys.join(', ')}).';
        throw DispatchException('The workflow has no input "$name"$has');
      }
    }
    return {
      for (final input in declared.values)
        input.name: given.containsKey(input.name)
            ? given[input.name]
            : input.required
            ? throw DispatchException('The input "${input.name}" is needed.')
            : input.defaultValue,
    };
  }

  AppVersion? _releaseVersion(DispatchRequest request, Set<String> kinds) {
    final text = request.releaseVersion;
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
    final worktree = await _git.createWorktree(
      mirror,
      name: 'dispatch-$runId',
      sha: sha,
    );
    try {
      final state = await VersionFiles(_workspaces(worktree.path))
          .read([joinScanPath(app.path, 'pubspec.yaml')]);
      return state.pubspec;
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

  Future<List<_PlannedJob>> _planJobs(
    WorkflowDefinition definition,
    RunContext run,
  ) async {
    final planned = <_PlannedJob>[];
    for (final (stage, stageDefinition) in definition.stages.indexed) {
      for (final job in stageDefinition.jobs) {
        for (final cell in expandMatrix(job, run.scope)) {
          final context = await _jobContext(job, cell, run, planned);
          if (job.condition != null &&
              !Expression.isTruthy(job.condition!.evaluate(context.scope))) {
            continue;
          }
          planned.add(await _planJob(job, cell, stage, context));
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
    final fallback =
        '${definition.id}'
        '${cell.isEmpty ? '' : ' (${cell.values.join(', ')})'}';
    final name = definition.name?.evaluate(scope);
    return _PlannedJob(
      id: context.jobId,
      definitionId: definition.id,
      cell: cell,
      stage: stage,
      name: name is String && name.isNotEmpty ? name : fallback,
      capabilities: [for (final need in placed) need.wire]..sort(),
      narrowed: narrowed,
      narrowing: narrowing,
      steps: steps,
    );
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

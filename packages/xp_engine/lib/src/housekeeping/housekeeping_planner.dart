import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/artifacts/artifact_record.dart';
import 'package:xp_engine/src/artifacts/artifact_repository.dart';
import 'package:xp_engine/src/clock/clock.dart';
import 'package:xp_engine/src/housekeeping/data_files.dart';
import 'package:xp_engine/src/housekeeping/housekeeping_plan.dart';
import 'package:xp_engine/src/jobs/job_record.dart';
import 'package:xp_engine/src/jobs/job_repository.dart';
import 'package:xp_engine/src/projects/project_repository.dart';
import 'package:xp_engine/src/releases/release_record.dart';
import 'package:xp_engine/src/releases/release_repository.dart';
import 'package:xp_engine/src/steps/shorebird/shorebird_release_record.dart';
import 'package:xp_engine/src/testing/test_run_repository.dart';

/// Decides what housekeeping removes (D-22, D-24), without removing anything.
///
/// The rules, all of which err on the side of keeping:
///
/// - **Artifacts.** The files of the newest `keepPerFlavor` builds of each
///   flavor stay. A build is a run (the jobs of a dispatch) and a flavor of
///   an app, so a release that builds iOS and Android and records a manifest
///   is one build. Pinned artifacts stay. Nothing is deleted from a release
///   that is not over (`draft` to `live`, `rejected` included: it can be built
///   again), from a job that has not finished, or from a run those releases
///   built.
/// - **Logs.** The logs of jobs that finished more than `logDays` ago go.
///   Their records go too, unless a release that is not over needs them, a
///   baseline test run belongs to them (D-21: the cascade of the job would
///   delete the baseline) or an artifact is kept with them.
/// - **Worktrees.** A job that succeeded or was cancelled needs its worktree
///   no more; one that failed keeps it for [failedWorktreeGrace] (it can be
///   resumed) and for as long as a release that is not over needs it. A
///   worktree of no job goes.
/// - **Mirrors.** Removing a project leaves its mirror (D-05); the mirrors of
///   repositories that are not projects go.
/// - **Flutter SDKs.** Those that no app pins in `.fvmrc`, no Shorebird
///   release was built with (every patch needs it, D-20) and no unfinished job
///   uses.
class HousekeepingPlanner {
  /// Creates the planner.
  new({
    required this._artifacts,
    required this._jobs,
    required this._releases,
    required this._projects,
    required this._testRuns,
    required this._shorebird,
    required this._files,
    required this._clock,
  });

  /// How long the worktree of a failed job is kept, for a resume.
  static const failedWorktreeGrace = Duration(days: 7);

  final ArtifactRepository _artifacts;
  final JobRepository _jobs;
  final ReleaseRepository _releases;
  final ProjectRepository _projects;
  final TestRunRepository _testRuns;
  final ShorebirdReleaseRepository _shorebird;
  final DataFiles _files;
  final Clock _clock;

  /// The plan for [retention].
  ///
  /// With [deleteArtifacts] false, retention is not part of the plan: no
  /// artifact is to go, which also decides which job records stay.
  Future<HousekeepingPlan> plan(
    RetentionSettings retention, {
    bool deleteArtifacts = true,
  }) async {
    final now = _clock.now();
    final jobs = await _jobs.list(states: JobState.values.toSet());
    final releases = await _releases.list();
    final open = _OpenReleases(releases);
    final artifactsByJob = {
      for (final job in jobs) job.id: await _artifacts.forJob(job.id),
    };

    final flavors = await _flavorPlans(
      jobs,
      artifactsByJob,
      releases,
      open,
      retention.keepPerFlavor,
      deleteArtifacts,
    );
    final expired = {
      for (final flavor in flavors)
        for (final record in flavor.expired) record.id,
    };

    final cutoff = now.subtract(Duration(days: retention.logDays));
    final logJobs = [
      for (final job in jobs)
        if (job.state.isFinished &&
            !(job.finishedAt ?? job.createdAt).isAfter(cutoff))
          job,
    ];
    final baselines = await _baselineJobs();
    final jobRows = [
      for (final job in logJobs)
        if (!open.protects(job) &&
            !baselines.contains(job.id) &&
            artifactsByJob[job.id]!.every((a) => expired.contains(a.id)))
          job,
    ];

    final jobsById = {for (final job in jobs) job.id: job};
    final worktrees = await _files.worktrees();
    final mirrors = await _files.mirrors();
    final sdks = await _files.flutterVersions();
    final pinned = await _pinnedFlutter(jobs);
    return HousekeepingPlan(
      retention: retention,
      flavors: flavors,
      logSizes: await _files.logSizes(),
      logJobs: logJobs,
      jobRows: jobRows,
      worktrees: worktrees,
      staleWorktrees: [
        for (final worktree in worktrees)
          if (_isStale(jobsById[worktree.name], open, now)) worktree,
      ],
      mirrors: mirrors,
      orphanMirrors: [
        for (final mirror in mirrors)
          if (await _projects.findBySourceKey(mirror.key) == null) mirror,
      ],
      sdks: sdks,
      unpinnedSdks: [
        for (final sdk in sdks)
          if (!pinned.contains(sdk.version)) sdk,
      ],
    );
  }

  // ------------------------------------------------------------- artifacts

  Future<List<FlavorPlan>> _flavorPlans(
    List<JobRecord> jobs,
    Map<String, List<ArtifactRecord>> artifactsByJob,
    List<ReleaseRecord> releases,
    _OpenReleases open,
    int keep,
    bool deleteArtifacts,
  ) async {
    final releasesById = {for (final r in releases) r.id: r};
    // flavor key -> run key -> the build.
    final flavors = <(String, String, String), Map<String, _Build>>{};
    for (final job in jobs) {
      final artifacts = artifactsByJob[job.id]!;
      if (artifacts.isEmpty) continue;
      final (app, flavor) = await _originOf(job, releasesById);
      final builds = flavors.putIfAbsent((
        job.projectId,
        app,
        flavor,
      ), () => {});
      builds
          .putIfAbsent(job.runId ?? job.id, _Build.new)
          .add(job, artifacts, protected: open.protects(job));
    }
    return [
      for (final MapEntry(key: (project, app, flavor), value: builds)
          in flavors.entries)
        _flavorPlan(project, app, flavor, builds.values, keep, deleteArtifacts),
    ];
  }

  FlavorPlan _flavorPlan(
    String project,
    String app,
    String flavor,
    Iterable<_Build> builds,
    int keep,
    bool deleteArtifacts,
  ) {
    final newestFirst = builds.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return FlavorPlan(
      projectId: project,
      app: app,
      flavor: flavor,
      builds: newestFirst.length,
      artifacts: [for (final build in newestFirst) ...build.artifacts],
      expired: [
        if (deleteArtifacts)
          for (final (rank, build) in newestFirst.indexed)
            if (rank >= keep && !build.protected)
              for (final artifact in build.artifacts)
                if (!artifact.pinned) artifact,
      ],
    );
  }

  /// The app path and flavor a job built: those of its release, or of the
  /// worktree its steps record.
  Future<(String, String)> _originOf(
    JobRecord job,
    Map<String, ReleaseRecord> releases,
  ) async {
    final release = releases[job.releaseId];
    if (release != null) return (release.appPath, release.flavor);
    for (final step in await _jobs.steps(job.id)) {
      final worktree = step.input['worktree'];
      if (worktree is! Map<String, dynamic>) continue;
      final scope = worktree['scope'];
      final flavor = scope is Map<String, dynamic> ? scope['flavor'] : null;
      return (
        worktree['appPath'] as String? ?? '.',
        flavor is String ? flavor : '',
      );
    }
    return ('.', '');
  }

  // ------------------------------------------------------------------ jobs

  Future<Set<String>> _baselineJobs() async => {
    for (final project in await _projects.list())
      for (final run in await _testRuns.baselines(project.id)) run.jobId,
  };

  bool _isStale(JobRecord? job, _OpenReleases open, DateTime now) {
    if (job == null) return true;
    return switch (job.state) {
      JobState.succeeded || JobState.cancelled => true,
      JobState.failed =>
        !open.protects(job) &&
            !(job.finishedAt ?? job.createdAt)
                .add(failedWorktreeGrace)
                .isAfter(now),
      _ => false,
    };
  }

  // --------------------------------------------------------------- flutter

  Future<Set<String>> _pinnedFlutter(List<JobRecord> jobs) async => {
    for (final project in await _projects.list())
      for (final app in project.profile.apps) ?app.flutterVersion,
    ...await _shorebird.flutterVersions(),
    for (final job in jobs)
      if (!job.state.isFinished) ?(await _jobs.tools(job.id))?.flutter,
  };
}

/// The releases that are not over, and what they keep alive.
class _OpenReleases {
  new(Iterable<ReleaseRecord> releases) {
    for (final release in releases) {
      if (release.state.isTerminal) continue;
      ids.add(release.id);
      runs.addAll(release.builds.map((build) => build.runId));
      final merge = release.mergeRunId;
      if (merge != null) runs.add(merge);
    }
  }

  final ids = <String>{};
  final runs = <String>{};

  /// Whether nothing of [job] may be deleted: it has not finished, or a
  /// release that is not over made it or built it.
  bool protects(JobRecord job) =>
      !job.state.isFinished ||
      ids.contains(job.releaseId) ||
      runs.contains(job.runId);
}

/// The jobs and artifacts of one run, for one flavor.
class _Build {
  final artifacts = <ArtifactRecord>[];
  bool protected = false;
  DateTime? _createdAt;

  /// When the newest job of the build was created.
  DateTime get createdAt => _createdAt!;

  void add(
    JobRecord job,
    List<ArtifactRecord> records, {
    required bool protected,
  }) {
    artifacts.addAll(records);
    this.protected |= protected;
    final known = _createdAt;
    if (known == null || job.createdAt.isAfter(known)) {
      _createdAt = job.createdAt;
    }
  }
}

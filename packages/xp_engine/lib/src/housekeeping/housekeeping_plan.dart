import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/artifacts/artifact_record.dart';
import 'package:xp_engine/src/housekeeping/data_files.dart';
import 'package:xp_engine/src/jobs/job_record.dart';

/// The artifacts of one flavor of an app and what retention does with them.
class FlavorPlan {
  /// Creates the plan.
  const new({
    required this.projectId,
    required this.app,
    required this.flavor,
    required this.builds,
    required this.artifacts,
    required this.expired,
  });

  /// The project.
  final String projectId;

  /// The path of the app.
  final String app;

  /// The flavor; empty for an app without flavors.
  final String flavor;

  /// How many builds (runs) made artifacts.
  final int builds;

  /// Every artifact of the flavor.
  final List<ArtifactRecord> artifacts;

  /// The artifacts retention deletes.
  final List<ArtifactRecord> expired;

  /// The usage, for the report.
  FlavorUsage toUsage() => FlavorUsage(
    projectId: projectId,
    app: app,
    flavor: flavor,
    builds: builds,
    artifacts: artifacts.length,
    usedBytes: _bytes(artifacts),
    reclaimableBytes: _bytes(expired),
  );

  static int _bytes(List<ArtifactRecord> records) =>
      records.fold(0, (sum, record) => sum + record.size);
}

/// Everything housekeeping would remove, decided and not yet done.
class HousekeepingPlan {
  /// Creates the plan.
  const new({
    required this.retention,
    required this.flavors,
    required this.logSizes,
    required this.logJobs,
    required this.jobRows,
    required this.worktrees,
    required this.staleWorktrees,
    required this.mirrors,
    required this.orphanMirrors,
    required this.sdks,
    required this.unpinnedSdks,
  });

  /// The settings the plan follows.
  final RetentionSettings retention;

  /// The artifacts by flavor.
  final List<FlavorPlan> flavors;

  /// The size of every job's log folder, by job id.
  final Map<String, int> logSizes;

  /// The finished jobs older than `logDays`: their logs go.
  final List<JobRecord> logJobs;

  /// Those among them whose records go too (nothing needs them).
  final List<JobRecord> jobRows;

  /// Every worktree.
  final List<WorktreeDirectory> worktrees;

  /// The worktrees nothing needs.
  final List<WorktreeDirectory> staleWorktrees;

  /// Every mirror.
  final List<MirrorDirectory> mirrors;

  /// The mirrors of repositories that are not projects.
  final List<MirrorDirectory> orphanMirrors;

  /// Every Flutter SDK in the cache.
  final List<FlutterDirectory> sdks;

  /// The SDKs no project, release or running job needs.
  final List<FlutterDirectory> unpinnedSdks;

  /// The artifacts retention deletes.
  List<ArtifactRecord> get expiredArtifacts => [
    for (final flavor in flavors) ...flavor.expired,
  ];

  /// The log folders that exist for the jobs whose logs go.
  List<JobRecord> get logsToDelete => [
    for (final job in logJobs)
      if (logSizes.containsKey(job.id)) job,
  ];

  /// What each category holds and would free.
  List<CategoryUsage> toCategories() {
    int sum(Iterable<int> sizes) => sizes.fold(0, (a, b) => a + b);
    final artifacts = [for (final flavor in flavors) ...flavor.artifacts];
    return [
      CategoryUsage(
        category: StorageCategory.artifacts,
        usedBytes: sum(artifacts.map((a) => a.size)),
        reclaimableBytes: sum(expiredArtifacts.map((a) => a.size)),
        items: expiredArtifacts.length,
      ),
      CategoryUsage(
        category: StorageCategory.logs,
        usedBytes: sum(logSizes.values),
        reclaimableBytes: sum(logsToDelete.map((j) => logSizes[j.id]!)),
        items: logsToDelete.length,
      ),
      CategoryUsage(
        category: StorageCategory.worktrees,
        usedBytes: sum(worktrees.map((w) => w.bytes)),
        reclaimableBytes: sum(staleWorktrees.map((w) => w.bytes)),
        items: staleWorktrees.length,
      ),
      CategoryUsage(
        category: StorageCategory.mirrors,
        usedBytes: sum(mirrors.map((m) => m.bytes)),
        reclaimableBytes: sum(orphanMirrors.map((m) => m.bytes)),
        items: orphanMirrors.length,
      ),
      CategoryUsage(
        category: StorageCategory.flutter,
        usedBytes: sum(sdks.map((s) => s.bytes)),
        reclaimableBytes: sum(unpinnedSdks.map((s) => s.bytes)),
        items: unpinnedSdks.length,
      ),
    ];
  }

  /// The report, made at [at].
  StorageReport toReport(DateTime at) => StorageReport(
    generatedAt: at,
    categories: toCategories(),
    flavors: [for (final flavor in flavors) flavor.toUsage()],
    retention: retention,
  );
}

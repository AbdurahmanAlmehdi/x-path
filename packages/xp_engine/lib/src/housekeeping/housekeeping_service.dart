import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/src/artifacts/artifact_repository.dart';
import 'package:xp_engine/src/artifacts/artifact_store.dart';
import 'package:xp_engine/src/clock/clock.dart';
import 'package:xp_engine/src/housekeeping/data_files.dart';
import 'package:xp_engine/src/housekeeping/housekeeping_exceptions.dart';
import 'package:xp_engine/src/housekeeping/housekeeping_plan.dart';
import 'package:xp_engine/src/housekeeping/housekeeping_planner.dart';
import 'package:xp_engine/src/housekeeping/housekeeping_repository.dart';
import 'package:xp_engine/src/jobs/job_repository.dart';
import 'package:xp_engine/src/tokens/device_token.dart';

/// The storage report, "free up space" and the daily pruning of logs (D-22,
/// D-24).
///
/// What goes is decided by the [HousekeepingPlanner]; this class reports it,
/// does it, and says who may.
///
/// Deleting is a gated action (D-13). A gate binds an approval to one project,
/// a commit and a version, and housekeeping spans every project, so it is
/// restricted the way abandoning a release is: only an `app` or `cli` token
/// may delete, and that token is the owner approving. An `mcp` or `runner`
/// token may read the report and dry-run, nothing more. The daily pruning of
/// logs is not a request: it is the retention policy of D-24.
class HousekeepingService {
  /// Creates the service.
  const new({
    required this._planner,
    required this._settings,
    required this._artifacts,
    required this._store,
    required this._jobs,
    required this._files,
    required this._clock,
  });

  final HousekeepingPlanner _planner;
  final HousekeepingRepository _settings;
  final ArtifactRepository _artifacts;
  final ArtifactStore _store;
  final JobRepository _jobs;
  final DataFiles _files;
  final Clock _clock;

  /// The retention in force.
  Future<RetentionSettings> retention() => _settings.retention();

  /// Replaces the retention with [settings], as the device [by].
  ///
  /// Throws a [HousekeepingForbiddenException] unless [by] is an `app` or
  /// `cli` token and a [HousekeepingRequestException] for a setting below 1.
  Future<RetentionSettings> setRetention(
    RetentionSettings settings, {
    required DeviceToken by,
  }) async {
    _requireOwner(by, 'change the retention');
    if (settings.keepPerFlavor < 1) {
      throw const HousekeepingRequestException(
        'keepPerFlavor must be at least 1.',
      );
    }
    if (settings.logDays < 1) {
      throw const HousekeepingRequestException('logDays must be at least 1.');
    }
    await _settings.saveRetention(settings);
    return settings;
  }

  /// What the engine keeps, and what [free] would give back. Deletes nothing.
  Future<StorageReport> report() async =>
      (await _planner.plan(await _settings.retention())).toReport(_clock.now());

  /// Frees up space as [request] says, as the device [by]: what would go for
  /// a dry run, what went otherwise.
  ///
  /// Throws a [HousekeepingForbiddenException] if the request deletes and
  /// [by] is not an `app` or `cli` token.
  Future<FreeSpaceResult> free(
    FreeSpaceRequest request, {
    required DeviceToken by,
  }) async {
    if (!request.dryRun) _requireOwner(by, 'free up space');
    final wanted = (request.categories ?? StorageCategory.values).toSet();
    final plan = await _planner.plan(
      await _settings.retention(),
      deleteArtifacts: wanted.contains(StorageCategory.artifacts),
    );
    if (request.dryRun) {
      return FreeSpaceResult(
        dryRun: true,
        categories: [
          for (final usage in plan.toCategories())
            if (wanted.contains(usage.category))
              FreedCategory(
                category: usage.category,
                bytes: usage.reclaimableBytes,
                items: usage.items,
              ),
        ],
      );
    }
    final failures = <String>[];
    final freed = <FreedCategory>[];
    for (final category in StorageCategory.values) {
      if (!wanted.contains(category)) continue;
      freed.add(switch (category) {
        StorageCategory.artifacts => await _deleteArtifacts(plan, failures),
        StorageCategory.logs => await _deleteLogs(plan, failures),
        StorageCategory.worktrees => await _deleteWorktrees(plan, failures),
        StorageCategory.mirrors => await _deleteMirrors(plan, failures),
        StorageCategory.flutter => await _deleteSdks(plan, failures),
      });
    }
    return FreeSpaceResult(
      dryRun: false,
      categories: freed,
      failures: failures,
    );
  }

  /// Prunes the logs and the records of the jobs that finished more than
  /// `logDays` ago (D-24), and notes the time. Artifacts, worktrees, mirrors
  /// and SDKs stay for the owner to free.
  Future<FreedCategory> pruneLogs() async {
    final plan = await _planner.plan(
      await _settings.retention(),
      deleteArtifacts: false,
    );
    final failures = <String>[];
    final freed = await _deleteLogs(plan, failures);
    await _settings.saveLogPrune(_clock.now());
    if (failures.isNotEmpty) throw HousekeepingException(failures.join(' '));
    return freed;
  }

  /// When the logs were last pruned, or `null` if never.
  Future<DateTime?> lastLogPrune() => _settings.lastLogPrune();

  // ---------------------------------------------------------------- doing

  Future<FreedCategory> _deleteArtifacts(
    HousekeepingPlan plan,
    List<String> failures,
  ) async {
    var bytes = 0;
    var items = 0;
    for (final record in plan.expiredArtifacts) {
      try {
        await _store.delete(record.path);
        await _artifacts.delete(record.id);
        bytes += record.size;
        items++;
      } on Object catch (error) {
        failures.add('Cannot delete artifact ${record.name}: $error');
      }
    }
    return FreedCategory(
      category: StorageCategory.artifacts,
      bytes: bytes,
      items: items,
    );
  }

  Future<FreedCategory> _deleteLogs(
    HousekeepingPlan plan,
    List<String> failures,
  ) async {
    var bytes = 0;
    var items = 0;
    final kept = <String>{};
    for (final job in plan.logJobs) {
      final size = plan.logSizes[job.id];
      if (size == null) continue;
      try {
        await _files.deleteLogs(job.id);
        bytes += size;
        items++;
      } on Object catch (error) {
        kept.add(job.id);
        failures.add('Cannot delete the logs of job ${job.id}: $error');
      }
    }
    for (final job in plan.jobRows) {
      // A job whose logs could not go keeps its record, and so does one that
      // still has an artifact (deleting the record would delete it too).
      if (kept.contains(job.id)) continue;
      try {
        if ((await _artifacts.forJob(job.id)).isNotEmpty) continue;
        await _jobs.delete(job.id);
      } on Object catch (error) {
        failures.add('Cannot delete the record of job ${job.id}: $error');
      }
    }
    return FreedCategory(
      category: StorageCategory.logs,
      bytes: bytes,
      items: items,
    );
  }

  Future<FreedCategory> _deleteWorktrees(
    HousekeepingPlan plan,
    List<String> failures,
  ) async {
    var bytes = 0;
    var items = 0;
    for (final worktree in plan.staleWorktrees) {
      try {
        await _files.deleteWorktree(worktree);
        bytes += worktree.bytes;
        items++;
      } on Object catch (error) {
        failures.add('Cannot delete worktree ${worktree.name}: $error');
      }
    }
    return FreedCategory(
      category: StorageCategory.worktrees,
      bytes: bytes,
      items: items,
    );
  }

  Future<FreedCategory> _deleteMirrors(
    HousekeepingPlan plan,
    List<String> failures,
  ) async {
    var bytes = 0;
    var items = 0;
    for (final mirror in plan.orphanMirrors) {
      try {
        await _files.deleteMirror(mirror);
        bytes += mirror.bytes;
        items++;
      } on Object catch (error) {
        failures.add('Cannot delete mirror ${mirror.githubRepoId}: $error');
      }
    }
    return FreedCategory(
      category: StorageCategory.mirrors,
      bytes: bytes,
      items: items,
    );
  }

  Future<FreedCategory> _deleteSdks(
    HousekeepingPlan plan,
    List<String> failures,
  ) async {
    var bytes = 0;
    var items = 0;
    for (final sdk in plan.unpinnedSdks) {
      try {
        await _files.deleteFlutterVersion(sdk);
        bytes += sdk.bytes;
        items++;
      } on Object catch (error) {
        failures.add('Cannot delete Flutter ${sdk.version}: $error');
      }
    }
    return FreedCategory(
      category: StorageCategory.flutter,
      bytes: bytes,
      items: items,
    );
  }

  static void _requireOwner(DeviceToken by, String what) {
    if (by.kind != DeviceTokenKind.app && by.kind != DeviceTokenKind.cli) {
      throw HousekeepingForbiddenException(
        'A ${by.kind.name} token cannot $what: only the app or `xp` do.',
      );
    }
  }
}

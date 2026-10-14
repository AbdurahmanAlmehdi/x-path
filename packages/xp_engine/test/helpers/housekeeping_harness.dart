import 'dart:convert';

import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import 'approval_harness.dart';
import 'notify_harness.dart';
import 'workflow_fixtures.dart';

/// Housekeeping over fakes, with the demo project in it.
class HousekeepingHarness {
  new _();

  /// Creates the harness.
  static Future<HousekeepingHarness> create() async {
    final harness = HousekeepingHarness._();
    await harness.projects.add(demoProject());
    return harness;
  }

  /// The time.
  final clock = ManualClock(DateTime.utc(2026, 10, 14, 9));

  /// The artifact records.
  final artifacts = InMemoryArtifactRepository();

  /// The artifact files.
  final store = InMemoryArtifactStore();

  /// The jobs.
  final jobs = InMemoryJobRepository();

  /// The releases.
  final releases = InMemoryReleaseRepository();

  /// The projects.
  final projects = InMemoryProjectRepository();

  /// The test runs.
  final testRuns = InMemoryTestRunRepository();

  /// The Shorebird releases.
  final shorebird = InMemoryShorebirdReleaseRepository();

  /// The folders of the data directory.
  final files = InMemoryDataFiles();

  /// The settings.
  final settings = InMemoryHousekeepingRepository();

  late final planner = HousekeepingPlanner(
    artifacts: artifacts,
    jobs: jobs,
    releases: releases,
    projects: projects,
    testRuns: testRuns,
    shorebird: shorebird,
    files: files,
    clock: clock,
  );

  late final service = HousekeepingService(
    planner: planner,
    settings: settings,
    artifacts: artifacts,
    store: store,
    jobs: jobs,
    files: files,
    clock: clock,
  );

  /// An `app` token.
  final DeviceToken owner = tokenOf(DeviceTokenKind.app);

  /// The time [days] days before now.
  DateTime ago({int days = 0, int hours = 0}) =>
      clock.now().subtract(Duration(days: days, hours: hours));

  int _artifacts = 0;

  /// Adds a job of the demo project with an artifact of [size] bytes per name
  /// in [names] (the files are in the store), made [days] days ago.
  ///
  /// The job belongs to [run] (its own run if `null`), builds [flavor] of the
  /// app at [app] (or has the step [input]) and, if it is a release job, to
  /// [release].
  Future<JobRecord> addBuild({
    required String id,
    required int days,
    String flavor = 'prod',
    String app = '.',
    String? run,
    String? release,
    JobState state = JobState.succeeded,
    List<String> names = const ['app.aab'],
    int size = 100,
    bool pinned = false,
    bool withSteps = true,
    Map<String, dynamic>? input,
  }) async {
    final job = jobRecord(
      id: id,
      state: state,
      runId: run ?? 'run_$id',
      releaseId: release,
      name: id,
      createdAt: ago(days: days),
      finishedAt: state.isFinished ? ago(days: days) : null,
    );
    await jobs.create(job, [
      if (withSteps)
        StepRecord(
          jobId: id,
          ordinal: 0,
          kind: 'build.android',
          sideEffect: false,
          input:
              input ??
              {
                'worktree': {
                  'appPath': app,
                  'scope': {'app': 'demo', 'flavor': flavor},
                },
              },
        ),
    ]);
    for (final name in names) {
      final path = '$id/$name';
      await store.write(path, Stream.value(utf8.encode('x' * size)));
      await artifacts.save(
        ArtifactRecord(
          id: 'art_${++_artifacts}',
          jobId: id,
          kind: ArtifactKind.aab,
          path: path,
          size: size,
          sha256: 'a' * 64,
          createdAt: ago(days: days),
          pinned: pinned,
        ),
      );
    }
    return job;
  }

  /// Which artifact files are left.
  List<String> get storedFiles => store.files.keys.toList()..sort();

  /// The paths of the artifact records that are left.
  Future<List<String>> recordedPaths() async => [
    for (final job in await jobs.list(states: JobState.values.toSet()))
      for (final record in await artifacts.forJob(job.id)) record.path,
  ]..sort();

  /// Adds a release in [state] whose builds were made by [runIds].
  Future<ReleaseRecord> addRelease(
    String id,
    ReleaseState state, {
    List<String> runIds = const [],
    String? mergeRunId,
  }) async {
    final record = releaseRecord(
      id: id,
      state: state,
      builds: [
        for (final (index, runId) in runIds.indexed)
          ReleaseBuild(
            build: index + 1,
            runId: runId,
            createdAt: DateTime.utc(2026, 10),
          ),
      ],
      mergeRunId: mergeRunId,
    );
    await releases.create(record);
    return record;
  }
}

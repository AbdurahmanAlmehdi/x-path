import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/housekeeping_harness.dart';
import '../../helpers/notify_harness.dart';
import '../../helpers/test_run_records.dart';

void main() {
  late HousekeepingHarness h;

  /// A job that finished [days] days ago, with a log of [size] bytes.
  Future<void> finished(
    String id, {
    required int days,
    JobState state = JobState.succeeded,
    int size = 10,
    String? release,
    List<String> names = const [],
  }) async {
    await h.addBuild(
      id: id,
      days: days,
      state: state,
      release: release,
      names: names,
    );
    h.files.logs[id] = size;
  }

  Future<List<String>> jobIds() async => [
    for (final job in await h.jobs.list(states: JobState.values.toSet()))
      job.id,
  ]..sort();

  setUp(() async => h = await HousekeepingHarness.create());

  group('the logs of finished jobs', () {
    test('are kept for 90 days and then pruned with the job record', () async {
      await finished('fresh', days: 89);
      await finished('old', days: 91, size: 25);
      await finished('older', days: 400, size: 5);

      final freed = await h.service.pruneLogs();

      expect(freed.category, StorageCategory.logs);
      expect(freed.bytes, 30);
      expect(freed.items, 2);
      expect(h.files.logs.keys, ['fresh']);
      expect(await jobIds(), ['fresh']);
      expect(h.files.deleted, ['logs old', 'logs older']);
    });

    test('are kept as long as the settings say', () async {
      await h.service.setRetention(
        const RetentionSettings(logDays: 7),
        by: h.owner,
      );
      await finished('week', days: 6);
      await finished('older', days: 8);

      await h.service.pruneLogs();

      expect(await jobIds(), ['week']);
    });

    test(
      'are pruned for failed and cancelled jobs, not for running ones',
      () async {
        await finished('failed', days: 100, state: JobState.failed);
        await finished('cancelled', days: 100, state: JobState.cancelled);
        await finished('running', days: 100, state: JobState.running);
        await finished(
          'waiting',
          days: 100,
          state: JobState.waitingForApproval,
        );

        await h.service.pruneLogs();

        expect(await jobIds(), ['running', 'waiting']);
      },
    );

    test('a job without a finish time counts from when it was made', () async {
      await h.jobs.create(
        jobRecord(id: 'odd', createdAt: h.ago(days: 100)),
        const [],
      );
      h.files.logs['odd'] = 1;

      await h.service.pruneLogs();

      expect(await jobIds(), isEmpty);
    });

    test(
      'a job without a log folder loses its record and nothing else',
      () async {
        await h.addBuild(id: 'quiet', days: 100, names: const []);

        final freed = await h.service.pruneLogs();

        expect(freed.items, 0);
        expect(await jobIds(), isEmpty);
        expect(h.files.deleted, isEmpty);
      },
    );

    test('are counted in the report only where a log folder exists', () async {
      await finished('old', days: 100, size: 25);
      await h.addBuild(id: 'quiet', days: 100, names: const []);

      final logs = (await h.service.report()).categories[1];

      expect(logs.category, StorageCategory.logs);
      expect(logs.usedBytes, 25);
      expect(logs.reclaimableBytes, 25);
      expect(logs.items, 1);
    });

    test('are pruned daily and the time is noted', () async {
      expect(await h.service.lastLogPrune(), isNull);

      await h.service.pruneLogs();

      expect(await h.service.lastLogPrune(), h.clock.now());
    });
  });

  group('the record of an old job stays', () {
    test('when its test run is the baseline', () async {
      await finished('baseline', days: 200);
      await finished('green', days: 200);
      await h.testRuns.save(
        testRunRecord(
          id: 'tst_old',
          jobId: 'green',
          createdAt: DateTime.utc(2026),
        ),
      );
      await h.testRuns.save(
        testRunRecord(
          id: 'tst_new',
          jobId: 'baseline',
          createdAt: DateTime.utc(2026, 2),
        ),
      );

      await h.service.pruneLogs();

      // Only the current baseline is protected; the logs of both go.
      expect(await jobIds(), ['baseline']);
      expect(h.files.logs, isEmpty);
      expect(await h.testRuns.forJob('baseline'), isNotNull);
    });

    test('when it is not a baseline run, it goes with its test run', () async {
      await finished('plain', days: 200);
      await h.testRuns.save(testRunRecord(jobId: 'plain', baseline: false));

      await h.service.pruneLogs();

      expect(await jobIds(), isEmpty);
    });

    test('when a release that is not over needs it', () async {
      await finished('release_job', days: 200, release: 'rel_1');
      await h.addRelease('rel_1', ReleaseState.live);

      await h.service.pruneLogs();

      expect(await jobIds(), ['release_job']);
      expect(h.files.logs, isEmpty);
    });

    test('when it has artifacts, which stay for the owner to free', () async {
      await finished('built', days: 200, names: ['app.aab']);

      await h.service.pruneLogs();

      expect(await jobIds(), ['built']);
      expect(h.files.logs, isEmpty);
      expect(h.storedFiles, ['built/app.aab']);
    });

    test('but goes once its artifacts do', () async {
      await finished('built', days: 200, names: ['app.aab']);
      await h.addBuild(id: 'new_1', days: 1);
      await h.addBuild(id: 'new_2', days: 2);
      await h.service.setRetention(
        const RetentionSettings(keepPerFlavor: 2),
        by: h.owner,
      );

      final result = await h.service.free(
        const FreeSpaceRequest(dryRun: false),
        by: h.owner,
      );

      expect(await jobIds(), ['new_1', 'new_2']);
      expect(h.storedFiles, ['new_1/app.aab', 'new_2/app.aab']);
      expect(
        result.categories.map((c) => (c.category, c.items)),
        containsAll([
          (StorageCategory.artifacts, 1),
          (StorageCategory.logs, 1),
        ]),
      );
    });

    test('when only some artifacts go, the job keeps the others', () async {
      await finished('built', days: 200, names: ['a.aab', 'b.aab']);
      await h.addBuild(id: 'new_1', days: 1);
      await h.addBuild(id: 'new_2', days: 2);
      await h.artifacts.setPinned('art_1', pinned: true);
      await h.service.setRetention(
        const RetentionSettings(keepPerFlavor: 2),
        by: h.owner,
      );

      await h.service.free(const FreeSpaceRequest(dryRun: false), by: h.owner);

      expect(await jobIds(), contains('built'));
      expect(h.storedFiles, contains('built/a.aab'));
    });

    test('when its artifact could not be deleted', () async {
      await finished('built', days: 200, names: ['app.aab']);
      await h.addBuild(id: 'new_1', days: 1);
      await h.addBuild(id: 'new_2', days: 2);
      await h.service.setRetention(
        const RetentionSettings(keepPerFlavor: 2),
        by: h.owner,
      );
      final failing = HousekeepingService(
        planner: h.planner,
        settings: h.settings,
        artifacts: h.artifacts,
        store: _NeverDeletes(h.store),
        jobs: h.jobs,
        files: h.files,
        clock: h.clock,
      );

      final result = await failing.free(
        const FreeSpaceRequest(dryRun: false),
        by: h.owner,
      );

      expect(result.failures, hasLength(1));
      expect(await jobIds(), contains('built'));
      expect(h.storedFiles, contains('built/app.aab'));
    });
  });

  group('failures', () {
    test('logs that cannot be deleted keep their job record', () async {
      await finished('stuck', days: 200);
      await finished('fine', days: 200);
      h.files.failOn = 'logs stuck';

      await expectLater(
        h.service.pruneLogs(),
        throwsA(
          isA<HousekeepingException>().having(
            (e) => e.message,
            'message',
            contains('Cannot delete the logs of job stuck'),
          ),
        ),
      );

      expect(await jobIds(), ['stuck']);
      // The pruning is noted even so: it ran.
      expect(await h.service.lastLogPrune(), h.clock.now());
    });

    test('a record that cannot be deleted is reported', () async {
      await finished('doomed', days: 200);
      final failing = HousekeepingService(
        planner: HousekeepingPlanner(
          artifacts: h.artifacts,
          jobs: _UndeletableJobs(h.jobs),
          releases: h.releases,
          projects: h.projects,
          testRuns: h.testRuns,
          shorebird: h.shorebird,
          files: h.files,
          clock: h.clock,
        ),
        settings: h.settings,
        artifacts: h.artifacts,
        store: h.store,
        jobs: _UndeletableJobs(h.jobs),
        files: h.files,
        clock: h.clock,
      );

      final result = await failing.free(
        const FreeSpaceRequest(
          dryRun: false,
          categories: [StorageCategory.logs],
        ),
        by: h.owner,
      );

      expect(result.failures.single, contains('record of job doomed'));
    });
  });
}

class _NeverDeletes implements ArtifactStore {
  new(this._inner);

  final InMemoryArtifactStore _inner;

  @override
  Future<void> delete(String path) async => throw StateError('no');

  @override
  Future<bool> exists(String path) => _inner.exists(path);

  @override
  Stream<List<int>> read(String path) => _inner.read(path);

  @override
  Future<void> write(String path, Stream<List<int>> content) =>
      _inner.write(path, content);
}

class _UndeletableJobs extends InMemoryJobRepository {
  new(this._inner);

  final InMemoryJobRepository _inner;

  @override
  Future<List<JobRecord>> list({required Set<JobState> states}) =>
      _inner.list(states: states);

  @override
  Future<List<StepRecord>> steps(String jobId) => _inner.steps(jobId);

  @override
  Future<JobTools?> tools(String jobId) => _inner.tools(jobId);

  @override
  Future<bool> delete(String id) async => throw StateError('locked');
}

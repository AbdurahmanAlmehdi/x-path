import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/housekeeping_harness.dart';

void main() {
  late HousekeepingHarness h;

  const apply = FreeSpaceRequest(
    dryRun: false,
    categories: [StorageCategory.artifacts],
  );

  Future<FreeSpaceResult> free() => h.service.free(apply, by: h.owner);

  setUp(() async {
    h = await HousekeepingHarness.create();
    await h.service.setRetention(
      const RetentionSettings(keepPerFlavor: 2),
      by: h.owner,
    );
  });

  group('the newest builds of a flavor', () {
    test('keep their files and the older ones lose them', () async {
      for (var day = 1; day <= 5; day++) {
        await h.addBuild(id: 'job_$day', days: day);
      }

      final result = await free();

      expect(h.storedFiles, ['job_1/app.aab', 'job_2/app.aab']);
      expect(await h.recordedPaths(), ['job_1/app.aab', 'job_2/app.aab']);
      expect(result.dryRun, isFalse);
      expect(result.categories.single.items, 3);
      expect(result.categories.single.bytes, 300);
      expect(result.failures, isEmpty);
    });

    test('are counted by build: a run of three jobs is one build', () async {
      await h.addBuild(id: 'ios', days: 1, run: 'run_a', names: ['a.ipa']);
      await h.addBuild(id: 'android', days: 1, run: 'run_a', names: ['a.aab']);
      await h.addBuild(
        id: 'manifest',
        days: 1,
        run: 'run_a',
        names: ['m.json'],
      );
      await h.addBuild(id: 'old_ios', days: 2, run: 'run_b', names: ['b.ipa']);
      await h.addBuild(id: 'older', days: 3, run: 'run_c', names: ['c.ipa']);

      await free();

      expect(h.storedFiles, [
        'android/a.aab',
        'ios/a.ipa',
        'manifest/m.json',
        'old_ios/b.ipa',
      ]);
    });

    test('are counted per flavor and per app', () async {
      for (final (flavor, app) in [
        ('prod', '.'),
        ('dev', '.'),
        ('prod', 'apps/other'),
      ]) {
        for (var day = 1; day <= 3; day++) {
          await h.addBuild(
            id: 'job_${flavor}_${app.length}_$day',
            days: day,
            flavor: flavor,
            app: app,
          );
        }
      }

      await free();

      // Two of three kept in each of the three groups.
      expect(h.storedFiles, hasLength(6));
      expect(h.storedFiles, everyElement(isNot(contains('_3/'))));
    });

    test(
      'a job with no worktree is a build of the app without a flavor',
      () async {
        for (var day = 1; day <= 3; day++) {
          await h.addBuild(id: 'job_$day', days: day, withSteps: false);
        }

        await free();

        expect(h.storedFiles, ['job_1/app.aab', 'job_2/app.aab']);
      },
    );

    test('a worktree without a flavor scope is the flavor ""', () async {
      for (var day = 1; day <= 3; day++) {
        await h.addBuild(
          id: 'job_$day',
          days: day,
          input: {
            'worktree': {'appPath': '.'},
          },
        );
      }

      final report = await h.service.report();

      expect(report.flavors.single.flavor, '');
      expect(report.flavors.single.builds, 3);
    });

    test('the settings decide how many', () async {
      for (var day = 1; day <= 4; day++) {
        await h.addBuild(id: 'job_$day', days: day);
      }
      await h.service.setRetention(
        const RetentionSettings(keepPerFlavor: 3),
        by: h.owner,
      );

      await free();

      expect(h.storedFiles, hasLength(3));
    });
  });

  group('what retention never deletes', () {
    for (final state in ReleaseState.values.where((s) => !s.isTerminal)) {
      test('the artifacts of a release that is ${state.wire}', () async {
        for (var day = 1; day <= 2; day++) {
          await h.addBuild(id: 'new_$day', days: day);
        }
        await h.addBuild(id: 'old', days: 200, release: 'rel_1');
        await h.addRelease('rel_1', state);

        await free();

        expect(h.storedFiles, contains('old/app.aab'));
        expect(await h.recordedPaths(), contains('old/app.aab'));
      });
    }

    for (final state in ReleaseState.values.where((s) => s.isTerminal)) {
      test('but those of a release that is ${state.wire} may go', () async {
        for (var day = 1; day <= 2; day++) {
          await h.addBuild(id: 'new_$day', days: day);
        }
        await h.addBuild(id: 'old', days: 200, release: 'rel_1');
        await h.addRelease('rel_1', state);

        await free();

        expect(h.storedFiles, isNot(contains('old/app.aab')));
      });
    }

    test('a job of the run that built a release in review', () async {
      for (var day = 1; day <= 2; day++) {
        await h.addBuild(id: 'new_$day', days: day);
      }
      await h.addBuild(id: 'build', days: 200, run: 'run_old');
      await h.addRelease('rel_1', ReleaseState.inReview, runIds: ['run_old']);

      await free();

      expect(h.storedFiles, contains('build/app.aab'));
    });

    test('a job of the run that merges a release that is live', () async {
      for (var day = 1; day <= 2; day++) {
        await h.addBuild(id: 'new_$day', days: day);
      }
      await h.addBuild(id: 'merge', days: 200, run: 'run_merge');
      await h.addRelease(
        'rel_1',
        ReleaseState.live,
        runIds: ['run_x'],
        mergeRunId: 'run_merge',
      );

      await free();

      expect(h.storedFiles, contains('merge/app.aab'));
    });

    test('pinned artifacts, but not their neighbours', () async {
      for (var day = 1; day <= 2; day++) {
        await h.addBuild(id: 'new_$day', days: day);
      }
      await h.addBuild(id: 'old', days: 200, names: ['a.aab', 'b.aab']);
      await h.artifacts.setPinned('art_3', pinned: true);

      final result = await free();

      expect(h.storedFiles, contains('old/a.aab'));
      expect(h.storedFiles, isNot(contains('old/b.aab')));
      expect(result.categories.single.items, 1);
    });

    test('the artifacts of a job that has not finished', () async {
      for (var day = 1; day <= 2; day++) {
        await h.addBuild(id: 'new_$day', days: day);
      }
      await h.addBuild(id: 'busy', days: 200, state: JobState.running);

      await free();

      expect(h.storedFiles, contains('busy/app.aab'));
    });

    test(
      'a build of a protected job whose neighbour in the run is not',
      () async {
        for (var day = 1; day <= 2; day++) {
          await h.addBuild(id: 'new_$day', days: day);
        }
        await h.addBuild(id: 'a', days: 200, run: 'run_old', release: 'rel_1');
        await h.addBuild(id: 'b', days: 201, run: 'run_old', names: ['b.aab']);
        await h.addRelease('rel_1', ReleaseState.live);

        await free();

        expect(h.storedFiles, containsAll(['a/app.aab', 'b/b.aab']));
      },
    );
  });

  group('a release in review', () {
    test('keeps its artifacts through the daily housekeeping too', () async {
      for (var day = 1; day <= 2; day++) {
        await h.addBuild(id: 'new_$day', days: day);
      }
      await h.addBuild(id: 'old', days: 200, release: 'rel_1');
      await h.addRelease('rel_1', ReleaseState.inReview);

      await h.service.pruneLogs();
      await free();
      await h.service.pruneLogs();

      expect(h.storedFiles, contains('old/app.aab'));
      expect(await h.jobs.get('old'), isNotNull);
    });
  });

  group('failures', () {
    test('a file that cannot be deleted keeps its record', () async {
      for (var day = 1; day <= 3; day++) {
        await h.addBuild(id: 'job_$day', days: day);
      }
      final failing = HousekeepingService(
        planner: h.planner,
        settings: h.settings,
        artifacts: h.artifacts,
        store: _FailingStore(h.store, 'job_3/app.aab'),
        jobs: h.jobs,
        files: h.files,
        clock: h.clock,
      );

      final result = await failing.free(apply, by: h.owner);

      expect(result.failures.single, contains('Cannot delete artifact'));
      expect(result.failures.single, contains('app.aab'));
      expect(result.categories.single.items, 0);
      expect(await h.recordedPaths(), hasLength(3));
    });
  });
}

class _FailingStore implements ArtifactStore {
  new(this._inner, this._failing);

  final InMemoryArtifactStore _inner;
  final String _failing;

  @override
  Future<void> delete(String path) async {
    if (path == _failing) throw StateError('disk on fire');
    await _inner.delete(path);
  }

  @override
  Future<bool> exists(String path) => _inner.exists(path);

  @override
  Stream<List<int>> read(String path) => _inner.read(path);

  @override
  Future<void> write(String path, Stream<List<int>> content) =>
      _inner.write(path, content);
}

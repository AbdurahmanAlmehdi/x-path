import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/housekeeping_harness.dart';
import '../../helpers/workflow_fixtures.dart';

void main() {
  late HousekeepingHarness h;

  WorktreeDirectory worktree(String job, {int repo = 42, int bytes = 1000}) =>
      WorktreeDirectory(
        key: '$repo',
        name: job,
        path: '/data/worktrees/$repo/$job',
        bytes: bytes,
      );

  Future<FreeSpaceResult> free(StorageCategory category) => h.service.free(
    FreeSpaceRequest(dryRun: false, categories: [category]),
    by: h.owner,
  );

  setUp(() async => h = await HousekeepingHarness.create());

  group('worktrees', () {
    test('of jobs that are done or gone are removed', () async {
      await h.addBuild(id: 'done', days: 1, names: const []);
      await h.addBuild(
        id: 'cancelled',
        days: 1,
        state: JobState.cancelled,
        names: const [],
      );
      h.files.worktreeList.addAll([
        worktree('done'),
        worktree('cancelled', bytes: 20),
        worktree('orphan', bytes: 3),
      ]);

      final result = await free(StorageCategory.worktrees);

      expect(h.files.worktreeList, isEmpty);
      expect(result.categories.single.items, 3);
      expect(result.categories.single.bytes, 1023);
    });

    test('of jobs that have not finished stay', () async {
      for (final state in [
        JobState.queued,
        JobState.running,
        JobState.interrupted,
        JobState.waitingForResume,
        JobState.waitingForApproval,
      ]) {
        await h.addBuild(id: state.wire, days: 30, state: state, names: []);
        h.files.worktreeList.add(worktree(state.wire));
      }

      final result = await free(StorageCategory.worktrees);

      expect(h.files.worktreeList, hasLength(5));
      expect(result.categories.single.items, 0);
    });

    test(
      'of a failed job stay for a week, so that it can be resumed',
      () async {
        await h.addBuild(
          id: 'fresh',
          days: 6,
          state: JobState.failed,
          names: [],
        );
        await h.addBuild(
          id: 'stale',
          days: 7,
          state: JobState.failed,
          names: [],
        );
        h.files.worktreeList.addAll([worktree('fresh'), worktree('stale')]);

        await free(StorageCategory.worktrees);

        expect(h.files.worktreeList.map((w) => w.name), ['fresh']);
      },
    );

    test('of a failed job of a release that is not over stay', () async {
      await h.addBuild(
        id: 'blocked',
        days: 60,
        state: JobState.failed,
        release: 'rel_1',
        names: [],
      );
      await h.addRelease('rel_1', ReleaseState.rejected);
      h.files.worktreeList.add(worktree('blocked'));

      await free(StorageCategory.worktrees);

      expect(h.files.worktreeList, hasLength(1));
    });

    test('of a job that succeeded in a release that is not over go', () async {
      await h.addBuild(id: 'built', days: 2, release: 'rel_1', names: []);
      await h.addRelease('rel_1', ReleaseState.inReview);
      h.files.worktreeList.add(worktree('built'));

      await free(StorageCategory.worktrees);

      expect(h.files.worktreeList, isEmpty);
    });

    test('that cannot be removed are reported', () async {
      await h.addBuild(id: 'done', days: 1, names: []);
      h.files.worktreeList.add(worktree('done'));
      h.files.failOn = 'worktree done';

      final result = await free(StorageCategory.worktrees);

      expect(result.failures.single, contains('Cannot delete worktree done'));
      expect(result.categories.single.items, 0);
    });
  });

  group('mirrors', () {
    MirrorDirectory mirror(int repo, {int bytes = 5000}) => MirrorDirectory(
      key: '$repo',
      path: '/data/mirrors/$repo.git',
      bytes: bytes,
    );

    test('of repositories that are no longer projects are removed', () async {
      h.files.mirrorList.addAll([mirror(42), mirror(7, bytes: 800)]);

      final result = await free(StorageCategory.mirrors);

      expect(h.files.mirrorList.map((m) => m.key), ['42']);
      expect(result.categories.single.bytes, 800);
      expect(result.categories.single.items, 1);
    });

    test('of a project on another host stay, by its source key', () async {
      const kept = 'h0123456789abcdef';
      const orphan = 'h1123456789abcdef';
      await h.projects.add(
        ProjectRecord(
          id: 'prj_bb',
          host: 'bitbucket.org',
          sourceKey: kept,
          fullName: 'ws/app',
          remote: 'git@bitbucket.org:ws/app.git',
          githubDefaultBranch: 'main',
          scan: const ProjectProfile(),
          findings: const [],
          scannedAt: DateTime.utc(2026),
        ),
      );
      h.files.mirrorList.addAll([
        for (final key in [kept, orphan])
          MirrorDirectory(key: key, path: '/data/mirrors/$key.git', bytes: 9),
      ]);

      final result = await free(StorageCategory.mirrors);

      expect(h.files.mirrorList.map((m) => m.key), [kept]);
      expect(result.categories.single.items, 1);
    });

    test('that cannot be removed are reported', () async {
      h.files.mirrorList.add(mirror(7));
      h.files.failOn = 'mirror 7';

      final result = await free(StorageCategory.mirrors);

      expect(result.failures.single, contains('Cannot delete mirror 7'));
    });
  });

  group('Flutter SDKs', () {
    FlutterDirectory sdk(String version, {int bytes = 2000}) =>
        FlutterDirectory(
          version: version,
          path: '/data/toolchains/flutter/$version',
          bytes: bytes,
        );

    test('that nothing pins are removed', () async {
      h.files.sdks.addAll([
        // The demo app pins 3.47.6 in .fvmrc.
        sdk('3.47.6'),
        sdk('3.35.4'),
        sdk('3.32.0'),
        sdk('3.24.0'),
        sdk('3.10.0', bytes: 77),
      ]);
      await h.shorebird.save(
        ShorebirdReleaseRecord(
          appId: 'sb-prod',
          version: AppVersion.parse('1.0.0+1'),
          platform: ShorebirdPlatform.android,
          flutterVersion: '3.35.4',
          jobId: 'job_x',
          recordedAt: DateTime.utc(2026),
        ),
      );
      await h.addBuild(
        id: 'running',
        days: 0,
        state: JobState.running,
        names: [],
      );
      await h.jobs.saveTools('running', const JobTools(flutter: '3.32.0'));
      await h.addBuild(id: 'done', days: 0, names: []);
      await h.jobs.saveTools('done', const JobTools(flutter: '3.24.0'));

      final result = await free(StorageCategory.flutter);

      expect(h.files.sdks.map((s) => s.version), [
        '3.47.6',
        '3.35.4',
        '3.32.0',
      ]);
      expect(result.categories.single.items, 2);
      expect(result.categories.single.bytes, 2077);
    });

    test('that cannot be removed are reported', () async {
      h.files.sdks.add(sdk('3.10.0'));
      h.files.failOn = 'flutter 3.10.0';

      final result = await free(StorageCategory.flutter);

      expect(result.failures.single, contains('Cannot delete Flutter 3.10.0'));
    });

    test('an app that pins no version keeps no SDK', () async {
      await h.projects.update(
        demoProject(
          apps: const [AppProfile(name: 'bare', path: '.')],
        ),
      );
      h.files.sdks.add(sdk('3.47.6'));

      await free(StorageCategory.flutter);

      expect(h.files.sdks, isEmpty);
    });
  });
}

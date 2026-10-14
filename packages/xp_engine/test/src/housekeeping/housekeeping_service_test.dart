import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/approval_harness.dart';
import '../../helpers/housekeeping_harness.dart';

void main() {
  late HousekeepingHarness h;

  setUp(() async => h = await HousekeepingHarness.create());

  group('retention settings', () {
    test('are 5 builds per flavor and 90 days of logs until changed', () async {
      expect(await h.service.retention(), const RetentionSettings());
    });

    test('are stored when the app or xp changes them', () async {
      for (final kind in [DeviceTokenKind.app, DeviceTokenKind.cli]) {
        final saved = await h.service.setRetention(
          RetentionSettings(keepPerFlavor: kind.index + 2, logDays: 30),
          by: tokenOf(kind),
        );

        expect(await h.service.retention(), saved);
      }
    });

    test('are not changed by an agent or a runner', () async {
      for (final kind in [DeviceTokenKind.mcp, DeviceTokenKind.runner]) {
        await expectLater(
          h.service.setRetention(
            const RetentionSettings(keepPerFlavor: 1),
            by: tokenOf(kind),
          ),
          throwsA(
            isA<HousekeepingForbiddenException>().having(
              (e) => e.message,
              'message',
              'A ${kind.name} token cannot change the retention: only the app '
                  'or `xp` do.',
            ),
          ),
        );
      }
      expect(await h.service.retention(), const RetentionSettings());
    });

    test('are at least 1', () async {
      await expectLater(
        h.service.setRetention(
          const RetentionSettings(keepPerFlavor: 0),
          by: h.owner,
        ),
        throwsA(isA<HousekeepingRequestException>()),
      );
      await expectLater(
        h.service.setRetention(
          const RetentionSettings(logDays: 0),
          by: h.owner,
        ),
        throwsA(
          isA<HousekeepingRequestException>().having(
            (e) => e.message,
            'message',
            'logDays must be at least 1.',
          ),
        ),
      );
    });
  });

  group('the report', () {
    test('says what each category holds and would free', () async {
      for (var day = 1; day <= 7; day++) {
        await h.addBuild(id: 'job_$day', days: day, size: 10);
      }
      h.files
        ..logs.addAll({'job_7': 4, 'job_1': 6})
        ..worktreeList.add(
          const WorktreeDirectory(
            githubRepoId: 42,
            name: 'job_7',
            path: '/w/job_7',
            bytes: 50,
          ),
        )
        ..mirrorList.add(
          const MirrorDirectory(githubRepoId: 9, path: '/m/9.git', bytes: 200),
        )
        ..sdks.add(
          const FlutterDirectory(version: '3.0.0', path: '/f', bytes: 900),
        );

      final report = await h.service.report();

      expect(report.generatedAt, h.clock.now());
      expect(report.retention, const RetentionSettings());
      expect(report.categories.map((c) => c.category), StorageCategory.values);
      expect(report.categories[0].usedBytes, 70);
      expect(report.categories[0].reclaimableBytes, 20);
      expect(report.categories[0].items, 2);
      expect(report.categories[1].usedBytes, 10);
      expect(report.categories[1].reclaimableBytes, 0);
      expect(report.categories[2].reclaimableBytes, 50);
      expect(report.categories[3].reclaimableBytes, 200);
      expect(report.categories[4].reclaimableBytes, 900);
      expect(report.usedBytes, 70 + 10 + 50 + 200 + 900);
      expect(report.reclaimableBytes, 20 + 50 + 200 + 900);
      expect(report.flavors.single.toJson(), {
        'projectId': 'prj_1',
        'app': '.',
        'flavor': 'prod',
        'builds': 7,
        'artifacts': 7,
        'usedBytes': 70,
        'reclaimableBytes': 20,
      });
    });

    test('of an empty engine is empty', () async {
      final report = await h.service.report();

      expect(report.flavors, isEmpty);
      expect(report.usedBytes, 0);
      expect(report.categories, hasLength(5));
    });

    test('deletes nothing', () async {
      for (var day = 1; day <= 7; day++) {
        await h.addBuild(id: 'job_$day', days: day);
      }

      await h.service.report();

      expect(h.storedFiles, hasLength(7));
    });
  });

  group('free up space', () {
    setUp(() async {
      for (var day = 1; day <= 7; day++) {
        await h.addBuild(id: 'job_$day', days: day);
      }
      h.files.mirrorList.add(
        const MirrorDirectory(githubRepoId: 9, path: '/m/9.git', bytes: 200),
      );
    });

    test('is a dry run unless told otherwise, for any token', () async {
      for (final kind in DeviceTokenKind.values) {
        final result = await h.service.free(
          const FreeSpaceRequest(),
          by: tokenOf(kind),
        );

        expect(result.dryRun, isTrue);
        expect(result.bytes, 200 + 200);
        expect(
          result.categories.map((c) => c.category),
          StorageCategory.values,
        );
      }
      expect(h.storedFiles, hasLength(7));
      expect(h.files.deleted, isEmpty);
    });

    test('a dry run of some categories says what they would free', () async {
      final result = await h.service.free(
        const FreeSpaceRequest(categories: [StorageCategory.mirrors]),
        by: h.owner,
      );

      expect(result.categories.single.category, StorageCategory.mirrors);
      expect(result.categories.single.bytes, 200);
    });

    test('deletes for the app and for xp', () async {
      final result = await h.service.free(
        const FreeSpaceRequest(dryRun: false),
        by: tokenOf(DeviceTokenKind.cli),
      );

      expect(result.dryRun, isFalse);
      expect(result.bytes, 400);
      expect(result.failures, isEmpty);
      expect(h.storedFiles, hasLength(5));
      expect(h.files.mirrorList, isEmpty);
    });

    test('does not delete for an agent or a runner', () async {
      for (final kind in [DeviceTokenKind.mcp, DeviceTokenKind.runner]) {
        await expectLater(
          h.service.free(
            const FreeSpaceRequest(dryRun: false),
            by: tokenOf(kind),
          ),
          throwsA(
            isA<HousekeepingForbiddenException>().having(
              (e) => e.toString(),
              'text',
              contains('${kind.name} token cannot free up space'),
            ),
          ),
        );
      }
      expect(h.storedFiles, hasLength(7));
      expect(h.files.mirrorList, hasLength(1));
    });

    test('only touches the categories asked for', () async {
      final result = await h.service.free(
        const FreeSpaceRequest(
          dryRun: false,
          categories: [StorageCategory.mirrors],
        ),
        by: h.owner,
      );

      expect(result.categories.map((c) => c.category), [
        StorageCategory.mirrors,
      ]);
      expect(h.storedFiles, hasLength(7));
    });
  });
}

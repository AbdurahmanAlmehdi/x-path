import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';

void main() {
  group('RetentionSettings', () {
    test('keeps five builds per flavor and 90 days of logs by default', () {
      const settings = RetentionSettings();

      expect(settings.keepPerFlavor, 5);
      expect(settings.logDays, 90);
      expect(settings.toJson(), {'keepPerFlavor': 5, 'logDays': 90});
    });

    test('round-trips through JSON', () {
      const settings = RetentionSettings(keepPerFlavor: 2, logDays: 30);

      expect(RetentionSettings.fromJson(settings.toJson()), settings);
    });

    test('reads a body with a missing field as the default', () {
      expect(
        RetentionSettings.fromJson(const {'keepPerFlavor': 9}),
        const RetentionSettings(keepPerFlavor: 9),
      );
    });
  });

  group('StorageReport', () {
    final report = StorageReport(
      generatedAt: DateTime.utc(2026, 10, 14, 9),
      categories: const [
        CategoryUsage(
          category: StorageCategory.artifacts,
          usedBytes: 1000,
          reclaimableBytes: 400,
          items: 2,
        ),
        CategoryUsage(
          category: StorageCategory.logs,
          usedBytes: 50,
          reclaimableBytes: 10,
          items: 1,
        ),
      ],
      flavors: const [
        FlavorUsage(
          projectId: 'prj_1',
          app: '.',
          flavor: 'prod',
          builds: 3,
          artifacts: 4,
          usedBytes: 1000,
          reclaimableBytes: 400,
        ),
      ],
      retention: const RetentionSettings(),
    );

    test('adds up the categories', () {
      expect(report.usedBytes, 1050);
      expect(report.reclaimableBytes, 410);
    });

    test('round-trips through JSON', () {
      expect(StorageReport.fromJson(report.toJson()), report);
      expect(report.toJson()['categories'], [
        {
          'category': 'artifacts',
          'usedBytes': 1000,
          'reclaimableBytes': 400,
          'items': 2,
        },
        {
          'category': 'logs',
          'usedBytes': 50,
          'reclaimableBytes': 10,
          'items': 1,
        },
      ]);
    });
  });

  group('FreeSpaceRequest', () {
    test('is a dry run of every category unless told otherwise', () {
      const request = FreeSpaceRequest();

      expect(request.dryRun, isTrue);
      expect(request.toJson(), {'dryRun': true});
      expect(FreeSpaceRequest.fromJson(const {}), request);
    });

    test('round-trips the categories', () {
      const request = FreeSpaceRequest(
        dryRun: false,
        categories: [StorageCategory.logs, StorageCategory.flutter],
      );

      expect(request.toJson(), {
        'dryRun': false,
        'categories': ['logs', 'flutter'],
      });
      expect(FreeSpaceRequest.fromJson(request.toJson()), request);
    });
  });

  group('FreeSpaceResult', () {
    test('adds up what was freed and round-trips', () {
      const result = FreeSpaceResult(
        dryRun: false,
        categories: [
          FreedCategory(
            category: StorageCategory.worktrees,
            bytes: 7,
            items: 1,
          ),
          FreedCategory(category: StorageCategory.mirrors, bytes: 5, items: 2),
        ],
        failures: ['Cannot remove mirror 3: busy.'],
      );

      expect(result.bytes, 12);
      expect(FreeSpaceResult.fromJson(result.toJson()), result);
    });

    test('has no failures by default', () {
      expect(
        const FreeSpaceResult(dryRun: true, categories: []).failures,
        isEmpty,
      );
    });
  });
}

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  group('the exceptions', () {
    test('say what is wrong', () {
      expect(
        const HousekeepingException('a').toString(),
        'HousekeepingException: a',
      );
      expect(
        const HousekeepingForbiddenException('b').toString(),
        'HousekeepingForbiddenException: b',
      );
      expect(
        const HousekeepingRequestException('c').toString(),
        'HousekeepingRequestException: c',
      );
      expect(const HousekeepingForbiddenException('b').message, 'b');
    });
  });

  group('InMemoryHousekeepingRepository', () {
    test('has the default retention and no pruning to begin with', () async {
      final repository = InMemoryHousekeepingRepository();

      expect(await repository.retention(), const RetentionSettings());
      expect(await repository.lastLogPrune(), isNull);
    });

    test('keeps what it is given', () async {
      final repository = InMemoryHousekeepingRepository();
      final at = DateTime.utc(2026, 10, 14);

      await repository.saveRetention(const RetentionSettings(keepPerFlavor: 9));
      await repository.saveLogPrune(at);

      expect(
        await repository.retention(),
        const RetentionSettings(keepPerFlavor: 9),
      );
      expect(await repository.lastLogPrune(), at);
    });
  });

  group('InMemoryDataFiles', () {
    test('lists and deletes what it has', () async {
      final files = InMemoryDataFiles()
        ..logs['job_1'] = 5
        ..worktreeList.add(
          const WorktreeDirectory(
            key: '1',
            name: 'job_1',
            path: '/w',
            bytes: 1,
          ),
        )
        ..mirrorList.add(const MirrorDirectory(key: '1', path: '/m', bytes: 1))
        ..sdks.add(const FlutterDirectory(version: '3', path: '/f', bytes: 1));

      expect(await files.logSizes(), {'job_1': 5});
      await files.deleteLogs('job_1');
      await files.deleteWorktree((await files.worktrees()).single);
      await files.deleteMirror((await files.mirrors()).single);
      await files.deleteFlutterVersion((await files.flutterVersions()).single);

      expect(files.deleted, [
        'logs job_1',
        'worktree job_1',
        'mirror 1',
        'flutter 3',
      ]);
      expect(await files.logSizes(), isEmpty);
      expect(await files.worktrees(), isEmpty);
      expect(await files.mirrors(), isEmpty);
      expect(await files.flutterVersions(), isEmpty);
    });
  });
}

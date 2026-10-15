import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xp_repositories/xp_repositories.dart';

void main() {
  group('Snapshot', () {
    test('compares by value and source', () {
      expect(const Snapshot(1), const Snapshot(1));
      expect(const Snapshot(1), isNot(const Snapshot(1, cached: true)));
      expect(const Snapshot(1).cached, isFalse);
    });
  });

  group('MemorySnapshotCache', () {
    test('reads what was written, as plain JSON', () async {
      final cache = MemorySnapshotCache();
      expect(await cache.read('projects'), isNull);
      await cache.write('projects', [
        {'id': 'prj_1'},
      ]);
      expect(await cache.read('projects'), [
        {'id': 'prj_1'},
      ]);
    });
  });

  group('FileSnapshotCache', () {
    late Directory directory;
    late FileSnapshotCache cache;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('xp_cache_');
      cache = FileSnapshotCache(p.join(directory.path, 'engine'));
    });

    tearDown(() => directory.deleteSync(recursive: true));

    test('is empty before anything is written', () async {
      expect(await cache.read('projects'), isNull);
    });

    test('keeps one file per key and replaces it', () async {
      await cache.write('job.job_1', {'id': 'job_1', 'state': 'queued'});
      await cache.write('job.job_1', {'id': 'job_1', 'state': 'running'});
      expect(await cache.read('job.job_1'), {
        'id': 'job_1',
        'state': 'running',
      });
      expect(
        File(p.join(cache.directory, 'job.job_1.json')).existsSync(),
        isTrue,
      );
    });

    test('keeps a key with odd characters inside the folder', () async {
      await cache.write('a/b c', 1);
      expect(File(p.join(cache.directory, 'a_b_c.json')).existsSync(), isTrue);
      expect(await cache.read('a/b c'), 1);
    });

    test('reads a file that is not JSON as missing', () async {
      Directory(cache.directory).createSync(recursive: true);
      File(p.join(cache.directory, 'projects.json')).writeAsStringSync('{');
      expect(await cache.read('projects'), isNull);
    });
  });
}

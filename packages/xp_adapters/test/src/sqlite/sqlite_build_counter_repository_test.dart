import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

ProjectRecord _project() => ProjectRecord(
  id: 'prj_1',
  host: 'github.com',
  sourceKey: '42',
  githubRepoId: 42,
  fullName: 'octo/app',
  remote: 'https://github.com/octo/app.git',
  githubDefaultBranch: 'main',
  scan: const ProjectProfile(
    apps: [
      AppProfile(name: 'app', path: '.'),
      AppProfile(name: 'tablet', path: 'apps/tablet'),
    ],
  ),
  findings: const [],
  scannedAt: DateTime.utc(2026),
);

void main() {
  late SqliteDatabase database;
  late SqliteBuildCounterRepository counters;

  int counterOf(String path, [SqliteDatabase? db]) =>
      (db ?? database).connection.select(
            'SELECT build_counter FROM app WHERE path = ?',
            [path],
          ).single['build_counter']
          as int;

  setUp(() async {
    database = SqliteDatabase.openInMemory();
    addTearDown(database.close);
    await SqliteProjectRepository(database, random: Random(1)).add(_project());
    counters = SqliteBuildCounterRepository(database);
  });

  Future<int> allocate(int seed, [String path = '.']) =>
      counters.allocate(projectId: 'prj_1', appPath: path, seed: seed);

  test('hands out one more than the counter', () async {
    expect(await allocate(0), 1);
    expect(await allocate(0), 2);
    expect(counterOf('.'), 2);
  });

  test('jumps over a seed that is higher than the counter', () async {
    expect(await allocate(3282), 3283);
    expect(await allocate(10), 3284);
    expect(await allocate(5000), 5001);
    expect(counterOf('.'), 5001);
  });

  test('keeps one counter per app', () async {
    await allocate(100);

    expect(await allocate(0, 'apps/tablet'), 1);
    expect(counterOf('.'), 101);
  });

  test('never hands a number back: the counter survives a rescan', () async {
    await allocate(77);
    await SqliteProjectRepository(
      database,
      random: Random(2),
    ).update(_project());

    expect(await allocate(0), 79);
  });

  test('peeks at the next number without taking it', () async {
    expect(await counters.peek(projectId: 'prj_1', appPath: '.', seed: 0), 1);
    expect(
      await counters.peek(projectId: 'prj_1', appPath: '.', seed: 3283),
      3284,
    );
    expect(counterOf('.'), 0);
    expect(
      () => counters.peek(projectId: 'prj_1', appPath: 'apps/x', seed: 0),
      throwsA(isA<UnknownAppException>()),
    );
    expect(
      () => counters.peek(projectId: 'prj_1', appPath: '.', seed: -1),
      throwsRangeError,
    );
  });

  test('refuses an unknown app and changes nothing', () async {
    await expectLater(
      allocate(9, 'apps/none'),
      throwsA(
        isA<UnknownAppException>().having(
          (e) => e.appPath,
          'appPath',
          'apps/none',
        ),
      ),
    );
    await expectLater(
      counters.allocate(projectId: 'prj_x', appPath: '.', seed: 0),
      throwsA(isA<UnknownAppException>()),
    );
    expect(counterOf('.'), 0);
  });

  test('refuses a negative seed', () {
    expect(allocate(-1), throwsRangeError);
  });

  test(
    'connections that take turns on one file never get the same number',
    () async {
      final directory = Directory.systemTemp.createTempSync('xp_counter_');
      addTearDown(() => directory.deleteSync(recursive: true));
      final path = p.join(directory.path, 'xpd.db');
      final first = SqliteDatabase.open(path);
      await SqliteProjectRepository(first, random: Random(1)).add(_project());
      final second = SqliteDatabase.open(path);
      addTearDown(first.close);
      addTearDown(second.close);
      final a = SqliteBuildCounterRepository(first);
      final b = SqliteBuildCounterRepository(second);

      final numbers = [
        await a.allocate(projectId: 'prj_1', appPath: '.', seed: 0),
        await b.allocate(projectId: 'prj_1', appPath: '.', seed: 0),
        await a.allocate(projectId: 'prj_1', appPath: '.', seed: 0),
        await b.allocate(projectId: 'prj_1', appPath: '.', seed: 10),
      ];

      expect(numbers, [1, 2, 3, 11]);
      expect(counterOf('.', first), 11);
    },
  );
}

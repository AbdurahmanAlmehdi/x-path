import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  group('SqliteReleaseRepository', () {
    late SqliteDatabase database;
    late SqliteReleaseRepository repository;
    final created = DateTime.utc(2026, 10, 14, 9);

    ReleaseRecord record(
      String id, {
      String projectId = 'prj_1',
      String appPath = '.',
      ReleaseState state = ReleaseState.draft,
      DateTime? at,
    }) => ReleaseRecord(
      id: id,
      projectId: projectId,
      appPath: appPath,
      flavor: 'prod',
      version: '1.2.0',
      build: 45,
      state: state,
      stores: {
        ReleaseStore.apple: StoreEntry(
          store: ReleaseStore.apple,
          state: StoreState.pending,
          source: StatusSource.upload,
          identity: const {'bundleId': 'ly.demo', 'country': 'us'},
          changedAt: created,
        ),
      },
      builds: [ReleaseBuild(build: 45, runId: 'run_$id', createdAt: created)],
      baseBranch: 'main',
      createdAt: at ?? created,
      updatedAt: at ?? created,
    );

    setUp(() {
      database = SqliteDatabase.openInMemory();
      addTearDown(database.close);
      database.connection
        ..execute(
          'INSERT INTO project (id, host, source_key, github_repo_id, remote, '
          'default_base_branch) VALUES '
          "('prj_1', 'github.com', '1', 1, 'a', 'main'), ('prj_2', "
          "'github.com', '2', 2, 'b', 'main')",
        )
        ..execute(
          'INSERT INTO app (id, project_id, path, framework, store_country) '
          "VALUES ('app_1', 'prj_1', '.', 'flutter', 'us'), "
          "('app_2', 'prj_1', 'packages/x', 'flutter', 'us'), "
          "('app_3', 'prj_2', '.', 'flutter', 'us')",
        );
      repository = SqliteReleaseRepository(database);
    });

    test('stores and reads a release, with its project and app', () async {
      await repository.create(record('rel_1'));

      expect(await repository.get('rel_1'), record('rel_1'));
      expect(await repository.get('rel_nope'), isNull);
    });

    test('keeps everything a release can have', () async {
      final full = record('rel_1').copyWith(
        state: ReleaseState.merged,
        branch: 'release/1.2.0',
        tag: 'v1.2.0+45',
        headSha: 'a' * 40,
        prNumber: 7,
        prUrl: 'https://github.com/o/r/pull/7',
        mergeCommit: 'b' * 40,
        mergeRunId: 'run_2',
        message: 'm',
        updatedAt: created.add(const Duration(hours: 1)),
      );
      await repository.create(record('rel_1'));

      await repository.update(full);

      expect(await repository.get('rel_1'), full);
    });

    test('replaces the stores and the builds', () async {
      await repository.create(record('rel_1'));
      final next = record('rel_1').copyWith(
        build: 46,
        stores: const {},
        builds: [
          ...record('rel_1').builds,
          ReleaseBuild(build: 46, runId: 'run_2', createdAt: created),
        ],
      );

      await repository.update(next);

      final read = (await repository.get('rel_1'))!;
      expect(read.build, 46);
      expect(read.stores, isEmpty);
      expect(read.builds.map((b) => b.build), [45, 46]);
    });

    test('lists newest first, and filters', () async {
      await repository.create(record('rel_1'));
      await repository.create(
        record('rel_2', appPath: 'packages/x', state: ReleaseState.live),
      );
      await repository.create(record('rel_3', projectId: 'prj_2'));
      await repository.create(
        record('rel_4', at: created.subtract(const Duration(days: 1))),
      );

      List<String> ids(List<ReleaseRecord> records) => [
        for (final record in records) record.id,
      ];
      expect(ids(await repository.list()), [
        'rel_3',
        'rel_2',
        'rel_1',
        'rel_4',
      ]);
      expect(ids(await repository.list(projectId: 'prj_1')), [
        'rel_2',
        'rel_1',
        'rel_4',
      ]);
      expect(ids(await repository.list(projectId: 'prj_1', appPath: '.')), [
        'rel_1',
        'rel_4',
      ]);
      expect(ids(await repository.list(states: {ReleaseState.live})), [
        'rel_2',
      ]);
      expect(
        ids(
          await repository.list(
            states: {ReleaseState.live, ReleaseState.draft},
            appPath: '.',
          ),
        ),
        ['rel_3', 'rel_1', 'rel_4'],
      );
      expect(ids(await repository.list(states: {})), isEmpty);
    });

    test('refuses a release of an app the project does not have', () async {
      await expectLater(
        repository.create(record('rel_1', appPath: 'nope')),
        throwsA(isA<SqliteException>()),
      );
    });

    test('keeps the app of a release when the project is rescanned', () async {
      await repository.create(record('rel_1'));

      final kept = database.connection.select(
        "SELECT count(*) AS n FROM app WHERE id = 'app_1'",
      );

      expect(kept.single['n'], 1);
      expect(
        () => database.connection.execute("DELETE FROM app WHERE id = 'app_1'"),
        throwsA(isA<SqliteException>()),
      );
    });
  });
}

import 'dart:math';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

const _plain = FlavorProfile(
  name: 'default',
  implicit: true,
  entrypoint: 'lib/main.dart',
  iosBundleId: 'com.example.app',
  androidAppId: 'com.example.app',
  prod: true,
  versionFiles: ['pubspec.yaml'],
);

const _dev = FlavorProfile(
  name: 'dev',
  entrypoint: 'lib/main_dev.dart',
  iosBundleId: 'com.example.dev',
  shorebird: true,
  shorebirdAppId: 'sb-dev',
  versionFiles: ['pubspec.yaml', 'ios/Runner/Info.plist'],
);

const _prod = FlavorProfile(
  name: 'prod',
  entrypoint: 'lib/main_prod.dart',
  prod: true,
);

ProjectRecord _record({
  String id = 'prj_1',
  int repoId = 42,
  List<AppProfile>? apps,
  ProfileEdits edits = const ProfileEdits(),
  String? localPath = '/work/app',
}) => ProjectRecord(
  id: id,
  host: 'github.com',
  sourceKey: '$repoId',
  githubRepoId: repoId,
  fullName: 'octo/app',
  remote: 'https://github.com/octo/app.git',
  githubDefaultBranch: 'main',
  localPath: localPath,
  scan: ProjectProfile(
    layout: ProjectLayout.melos,
    apps:
        apps ??
        const [
          AppProfile(name: 'app', path: '.', flavors: [_dev, _prod]),
          AppProfile(
            name: 'tablet',
            path: 'apps/tablet',
            storeCountry: 'de',
            flavors: [_plain],
          ),
        ],
    branches: const BranchLayout(
      defaultBranch: 'main',
      releaseBranches: ['release/1.0'],
    ),
    workflows: const [
      RepoWorkflow(path: 'codemagic.yaml', provider: 'codemagic'),
    ],
  ),
  findings: const [
    Finding(
      severity: FindingSeverity.warning,
      code: 'fvmrc_missing',
      message: 'm',
      fix: 'f',
      path: '.fvmrc',
      app: '.',
    ),
  ],
  scannedAt: DateTime.utc(2026, 10, 13, 8, 30, 15, 123, 456),
  edits: edits,
);

void main() {
  late SqliteDatabase database;
  late SqliteProjectRepository repository;

  Database db() => database.connection;

  List<Map<String, Object?>> rows(
    String sql, [
    List<Object?> args = const [],
  ]) => [
    for (final row in db().select(sql, args)) {...row},
  ];

  setUp(() {
    database = SqliteDatabase.openInMemory();
    addTearDown(database.close);
    repository = SqliteProjectRepository(database, random: Random(7));
  });

  test('starts empty', () async {
    expect(await repository.list(), isEmpty);
    expect(await repository.get('prj_1'), isNull);
    expect(await repository.findBySourceKey('42'), isNull);
  });

  group('add', () {
    test('stores everything and reads it back', () async {
      final record = _record(
        edits: const ProfileEdits(
          defaultBaseBranch: 'dev',
          apps: [AppEdit(path: '.', storeCountry: 'ly')],
        ),
      );

      await repository.add(record);

      expect(await repository.get('prj_1'), record);
      expect(await repository.findBySourceKey('42'), record);
      expect(await repository.list(), [record]);
    });

    test('stores a project that is not on GitHub', () async {
      final record = ProjectRecord(
        id: 'prj_bb',
        host: 'bitbucket.org',
        sourceKey: 'h0123456789abcdef',
        fullName: 'ws/repo',
        remote: 'git@bitbucket.org:ws/repo.git',
        githubDefaultBranch: 'main',
        scan: const ProjectProfile(),
        findings: const [],
        scannedAt: DateTime.utc(2026),
      );

      await repository.add(record);

      expect(await repository.findBySourceKey('h0123456789abcdef'), record);
      expect((await repository.get('prj_bb'))!.githubRepoId, isNull);
      expect(
        () => repository.add(
          ProjectRecord(
            id: 'prj_gh',
            host: 'bitbucket.org',
            sourceKey: 'h1123456789abcdef',
            githubRepoId: 7,
            fullName: 'ws/repo',
            remote: 'r',
            githubDefaultBranch: 'main',
            scan: const ProjectProfile(),
            findings: const [],
            scannedAt: DateTime.utc(2026),
          ),
        ),
        throwsA(isA<SqliteException>()),
        reason: 'only a project on GitHub has a GitHub repository id',
      );
    });

    test('lists projects in the order they were added', () async {
      await repository.add(_record(id: 'prj_b', repoId: 2));
      await repository.add(_record(id: 'prj_a', repoId: 1));

      expect((await repository.list()).map((r) => r.id), ['prj_b', 'prj_a']);
    });

    test('keeps no local path for a project added by remote', () async {
      await repository.add(_record(localPath: null));

      expect((await repository.get('prj_1'))!.localPath, isNull);
    });

    test('puts the effective base branch in its column', () async {
      await repository.add(
        _record(edits: const ProfileEdits(defaultBaseBranch: 'dev')),
      );

      expect(
        rows('SELECT default_base_branch, github_repo_id, remote FROM project'),
        [
          {
            'default_base_branch': 'dev',
            'github_repo_id': 42,
            'remote': 'https://github.com/octo/app.git',
          },
        ],
      );
    });

    test('writes the apps and flavors of the effective profile', () async {
      await repository.add(
        _record(
          edits: const ProfileEdits(
            apps: [
              AppEdit(
                path: '.',
                storeCountry: 'ly',
                flavors: [FlavorEdit(name: 'prod', shorebird: true)],
              ),
            ],
          ),
        ),
      );

      expect(
        rows(
          'SELECT path, framework, store_country, build_counter FROM app '
          'ORDER BY path',
        ),
        [
          {
            'path': '.',
            'framework': 'flutter',
            'store_country': 'ly',
            'build_counter': 0,
          },
          {
            'path': 'apps/tablet',
            'framework': 'flutter',
            'store_country': 'de',
            'build_counter': 0,
          },
        ],
      );
      expect(
        rows(
          'SELECT f.name, f.entrypoint, f.ios_bundle_id, f.android_app_id, '
          'f.shorebird, f.prod, f.version_files, a.path FROM flavor f '
          'JOIN app a ON a.id = f.app_id ORDER BY a.path, f.name',
        ),
        [
          {
            'name': 'dev',
            'entrypoint': 'lib/main_dev.dart',
            'ios_bundle_id': 'com.example.dev',
            'android_app_id': null,
            'shorebird': 1,
            'prod': 0,
            'version_files': '["pubspec.yaml","ios/Runner/Info.plist"]',
            'path': '.',
          },
          {
            'name': 'prod',
            'entrypoint': 'lib/main_prod.dart',
            'ios_bundle_id': null,
            'android_app_id': null,
            'shorebird': 1,
            'prod': 1,
            'version_files': '[]',
            'path': '.',
          },
          {
            'name': 'default',
            'entrypoint': 'lib/main.dart',
            'ios_bundle_id': 'com.example.app',
            'android_app_id': 'com.example.app',
            'shorebird': 0,
            'prod': 1,
            'version_files': '["pubspec.yaml"]',
            'path': 'apps/tablet',
          },
        ],
      );
    });

    test('refuses a second project for a repository', () async {
      await repository.add(_record());

      expect(
        () => repository.add(_record(id: 'prj_2')),
        throwsA(isA<SqliteException>()),
      );
      expect(await repository.list(), hasLength(1));
    });

    test('adds nothing when writing the profile fails', () async {
      db().execute(
        'CREATE TRIGGER no_apps BEFORE INSERT ON app '
        "BEGIN SELECT RAISE(ABORT, 'no'); END",
      );

      await expectLater(
        repository.add(_record()),
        throwsA(isA<SqliteException>()),
      );
      expect(await repository.list(), isEmpty);
    });
  });

  group('update', () {
    test('replaces the stored project', () async {
      await repository.add(_record());
      final changed = _record().copyWith(
        fullName: 'octo/renamed',
        remote: 'https://github.com/octo/renamed.git',
        githubDefaultBranch: 'develop',
        findings: const [],
        scannedAt: DateTime.utc(2027),
        edits: const ProfileEdits(defaultBaseBranch: 'dev'),
      );

      await repository.update(changed);

      expect(await repository.get('prj_1'), changed);
      expect(await repository.list(), [changed]);
    });

    test(
      'keeps the id and build counter of an app that is still there',
      () async {
        await repository.add(_record());
        final before = rows('SELECT id, path FROM app ORDER BY path');
        final flavorsBefore = rows('SELECT id, name FROM flavor ORDER BY name');
        db().execute('UPDATE app SET build_counter = 77 WHERE path = ?', ['.']);

        await repository.update(
          _record(
            edits: const ProfileEdits(
              apps: [
                AppEdit(
                  path: '.',
                  storeCountry: 'ly',
                  flavors: [FlavorEdit(name: 'dev', prod: true)],
                ),
              ],
            ),
          ),
        );

        expect(rows('SELECT id, path FROM app ORDER BY path'), before);
        expect(
          rows('SELECT id, name FROM flavor ORDER BY name'),
          flavorsBefore,
        );
        expect(
          rows('SELECT store_country, build_counter FROM app WHERE path = ?', [
            '.',
          ]),
          [
            {'store_country': 'ly', 'build_counter': 77},
          ],
        );
        expect(rows("SELECT prod FROM flavor WHERE name = 'dev'"), [
          {'prod': 1},
        ]);
      },
    );

    test('drops the apps and flavors a rescan no longer finds', () async {
      await repository.add(_record());

      await repository.update(
        _record(
          apps: const [
            AppProfile(name: 'app', path: '.', flavors: [_prod]),
          ],
        ),
      );

      expect(rows('SELECT path FROM app'), [
        {'path': '.'},
      ]);
      expect(rows('SELECT name FROM flavor'), [
        {'name': 'prod'},
      ]);
    });

    test('drops every app when the scan finds none', () async {
      await repository.add(_record());

      await repository.update(_record(apps: const []));

      expect(rows('SELECT path FROM app'), isEmpty);
    });

    test('keeps an app that has releases', () async {
      await repository.add(_record());
      final appId = db()
          .select("SELECT id FROM app WHERE path = '.'")
          .single['id'];
      db().execute(
        'INSERT INTO release (id, app_id, version, build, state) '
        "VALUES ('r1', ?, '1.0.0', 1, 'live')",
        [appId],
      );

      await repository.update(
        _record(
          apps: const [AppProfile(name: 'tablet', path: 'apps/tablet')],
        ),
      );

      expect(rows('SELECT path FROM app ORDER BY path'), [
        {'path': '.'},
        {'path': 'apps/tablet'},
      ]);
    });

    test('refuses a project that is not stored', () async {
      await expectLater(
        repository.update(_record()),
        throwsA(isA<StateError>()),
      );
      expect(rows('SELECT id FROM app'), isEmpty);
    });
  });

  group('remove', () {
    test('deletes the project with its apps and flavors', () async {
      await repository.add(_record());

      expect(await repository.remove('prj_1'), isTrue);
      expect(await repository.remove('prj_1'), isFalse);

      expect(await repository.list(), isEmpty);
      expect(rows('SELECT id FROM app'), isEmpty);
      expect(rows('SELECT id FROM flavor'), isEmpty);
    });

    test('refuses while releases refer to the project', () async {
      await repository.add(_record());
      final appId = db()
          .select("SELECT id FROM app WHERE path = '.'")
          .single['id'];
      db().execute(
        'INSERT INTO release (id, app_id, version, build, state) '
        "VALUES ('r1', ?, '1.0.0', 1, 'live')",
        [appId],
      );

      await expectLater(
        repository.remove('prj_1'),
        throwsA(isA<ProjectInUseException>()),
      );
      expect(await repository.get('prj_1'), isNotNull);
      expect(rows('SELECT id FROM app'), hasLength(2));
    });

    test('lets other database errors through', () async {
      await repository.add(_record());
      db().execute(
        'CREATE TRIGGER no_delete BEFORE DELETE ON project '
        "BEGIN SELECT RAISE(ABORT, 'no'); END",
      );

      await expectLater(
        repository.remove('prj_1'),
        throwsA(isA<SqliteException>()),
      );
    });
  });

  test('ids come from a secure random by default', () async {
    final unseeded = SqliteProjectRepository(database);

    await unseeded.add(_record());

    expect(
      rows('SELECT id FROM app').map((row) => row['id']),
      everyElement(matches(RegExp(r'^app_[0-9a-f]{16}$'))),
    );
  });

  test('seeded ids are repeatable and distinct', () async {
    await repository.add(_record());

    final ids = [
      ...rows('SELECT id FROM app'),
      ...rows('SELECT id FROM flavor'),
    ].map((row) => row['id']).toSet();

    expect(ids, hasLength(5));
  });
}

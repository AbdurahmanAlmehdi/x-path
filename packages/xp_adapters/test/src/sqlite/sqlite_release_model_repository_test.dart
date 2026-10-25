import 'dart:math';

import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  late SqliteDatabase database;
  late SqliteReleaseModelRepository repository;

  setUp(() async {
    database = SqliteDatabase.openInMemory();
    addTearDown(database.close);
    await SqliteProjectRepository(database, random: Random(1)).add(
      ProjectRecord(
        id: 'prj_1',
        host: 'github.com',
        sourceKey: '42',
        githubRepoId: 42,
        fullName: 'octo/app',
        remote: 'https://github.com/octo/app.git',
        githubDefaultBranch: 'main',
        scan: const ProjectProfile(),
        findings: const [],
        scannedAt: DateTime.utc(2026),
      ),
    );
    repository = SqliteReleaseModelRepository(database);
  });

  test('gives the default model for a project that has none stored', () async {
    expect(await repository.get('prj_1'), const ReleaseModel());
  });

  test('stores a model and reads it back', () async {
    const model = ReleaseModel(
      branchPattern: 'rel/{version}',
      tagPattern: '{app}/v{version}+{build}',
    );

    await repository.save('prj_1', model);

    expect(await repository.get('prj_1'), model);
    expect(
      database.connection
          .select('SELECT release_model FROM project')
          .single['release_model'],
      contains('"tagPattern":"{app}/v{version}+{build}"'),
    );
  });

  test('survives a rescan of the project', () async {
    const model = ReleaseModel(branchPattern: 'rel/{version}');
    await repository.save('prj_1', model);

    database.connection.execute(
      'UPDATE project SET full_name = ? WHERE id = ?',
      ['octo/renamed', 'prj_1'],
    );

    expect(await repository.get('prj_1'), model);
  });

  test('refuses an unknown project', () {
    expect(repository.get('nope'), throwsA(isA<ProjectNotFoundException>()));
    expect(
      repository.save('nope', const ReleaseModel()),
      throwsA(isA<ProjectNotFoundException>()),
    );
  });

  test('refuses a stored model that is not valid', () {
    database.connection.execute(
      'UPDATE project SET release_model = ? WHERE id = ?',
      ['{"tagPattern":"v{version}"}', 'prj_1'],
    );

    expect(repository.get('prj_1'), throwsFormatException);
  });
}

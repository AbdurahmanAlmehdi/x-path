import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:xp_adapters/xp_adapters.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

final _created = DateTime.utc(2026, 10, 13, 9, 30, 15, 123, 456);

ArtifactRecord _record(
  String id, {
  String jobId = 'job_1',
  ArtifactKind kind = ArtifactKind.apk,
  String? name,
  bool pinned = false,
  DateTime? createdAt,
}) => ArtifactRecord(
  id: id,
  jobId: jobId,
  kind: kind,
  path: '$jobId/${name ?? '$id.apk'}',
  size: 1234,
  sha256: 'ab' * 32,
  pinned: pinned,
  createdAt: createdAt ?? _created,
);

void main() {
  late SqliteDatabase database;
  late SqliteArtifactRepository repository;

  setUp(() {
    database = SqliteDatabase.openInMemory();
    addTearDown(database.close);
    database.connection
      ..execute(
        'INSERT INTO project (id, github_repo_id, remote, '
        "default_base_branch) VALUES ('prj_1', 1, 'r', 'main')",
      )
      ..execute(
        'INSERT INTO workflow (id, project_id, name) '
        "VALUES ('wf_1', 'prj_1', 'w')",
      )
      ..execute(
        'INSERT INTO workflow_version (id, workflow_id, version, yaml) '
        "VALUES ('wfv_1', 'wf_1', 1, '')",
      );
    for (final job in ['job_1', 'job_2']) {
      database.connection.execute(
        'INSERT INTO job (id, workflow_version_id, project_id, state) '
        "VALUES ('$job', 'wfv_1', 'prj_1', 'running')",
      );
    }
    repository = SqliteArtifactRepository(database);
  });

  test('stores a record and reads it back with microsecond time', () async {
    await repository.save(_record('art_1', pinned: true));

    expect(await repository.get('art_1'), _record('art_1', pinned: true));
    expect(await repository.get('art_2'), isNull);
  });

  test('stores every kind by its wire name', () async {
    for (final kind in ArtifactKind.values) {
      await repository.save(_record('art_${kind.wire}', kind: kind));
    }

    final kinds = database.connection
        .select('SELECT kind FROM artifact ORDER BY rowid')
        .map((row) => row['kind']);
    expect(kinds, ArtifactKind.values.map((kind) => kind.wire));
    expect(
      (await repository.get('art_shorebird_symbols'))!.kind,
      ArtifactKind.shorebirdSymbols,
    );
  });

  test('replaces the record with the same id', () async {
    await repository.save(_record('art_1'));
    await repository.save(
      _record('art_1', createdAt: _created.add(const Duration(hours: 1))),
    );

    final records = await repository.forJob('job_1');
    expect(records, hasLength(1));
    expect(records.single.createdAt, _created.add(const Duration(hours: 1)));
  });

  test('finds a record by job and path', () async {
    await repository.save(_record('art_1'));

    expect(
      (await repository.findByPath('job_1', 'job_1/art_1.apk'))?.id,
      'art_1',
    );
    expect(await repository.findByPath('job_2', 'job_1/art_1.apk'), isNull);
    expect(await repository.findByPath('job_1', 'job_1/other.apk'), isNull);
  });

  test('keeps one file per path for a job', () async {
    await repository.save(_record('art_1', name: 'dev.apk'));

    expect(
      () => repository.save(_record('art_2', name: 'dev.apk')),
      throwsA(isA<SqliteException>()),
    );
  });

  test('lists the artifacts of a job, oldest first', () async {
    await repository.save(
      _record('art_2', createdAt: _created.add(const Duration(minutes: 1))),
    );
    await repository.save(_record('art_1'));
    await repository.save(_record('art_3', jobId: 'job_2'));

    expect((await repository.forJob('job_1')).map((r) => r.id), [
      'art_1',
      'art_2',
    ]);
    expect(await repository.forJob('job_9'), isEmpty);
  });

  test('pins and unpins', () async {
    await repository.save(_record('art_1'));

    expect((await repository.setPinned('art_1', pinned: true))!.pinned, isTrue);
    expect((await repository.get('art_1'))!.pinned, isTrue);
    expect(
      (await repository.setPinned('art_1', pinned: false))!.pinned,
      isFalse,
    );
    expect(await repository.setPinned('art_9', pinned: true), isNull);
  });

  test('is deleted with its job', () async {
    await repository.save(_record('art_1'));

    database.connection.execute("DELETE FROM job WHERE id = 'job_1'");

    expect(await repository.get('art_1'), isNull);
  });

  test('a row of version 4, without a time, reads as the epoch', () async {
    database.connection.execute(
      'INSERT INTO artifact (id, job_id, kind, path, size, sha256) '
      "VALUES ('old', 'job_1', 'ipa', 'job_1/a.ipa', 5, 'abc')",
    );

    expect(
      (await repository.get('old'))!.createdAt,
      DateTime.fromMicrosecondsSinceEpoch(0, isUtc: true),
    );
  });
}

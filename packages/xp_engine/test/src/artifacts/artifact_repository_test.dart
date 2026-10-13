import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  late InMemoryArtifactRepository repository;

  ArtifactRecord record(String id, {String jobId = 'job_1', String? name}) =>
      ArtifactRecord(
        id: id,
        jobId: jobId,
        kind: ArtifactKind.apk,
        path: '$jobId/${name ?? '$id.apk'}',
        size: 1,
        sha256: 'a' * 64,
        createdAt: DateTime.utc(2026),
      );

  setUp(() => repository = InMemoryArtifactRepository());

  test('stores records and finds them by id and by path', () async {
    await repository.save(record('a'));

    expect(await repository.get('a'), record('a'));
    expect(await repository.get('b'), isNull);
    expect(await repository.findByPath('job_1', 'job_1/a.apk'), record('a'));
    expect(await repository.findByPath('job_2', 'job_1/a.apk'), isNull);
    expect(await repository.findByPath('job_1', 'job_1/b.apk'), isNull);
  });

  test('replaces the record with the same id', () async {
    await repository.save(record('a'));
    await repository.save(record('a', name: 'other.apk'));

    expect((await repository.forJob('job_1')).single.name, 'other.apk');
  });

  test('lists the records of one job in the order they were stored', () async {
    await repository.save(record('a'));
    await repository.save(record('b', jobId: 'job_2'));
    await repository.save(record('c'));

    expect((await repository.forJob('job_1')).map((r) => r.id), ['a', 'c']);
    expect(await repository.forJob('job_3'), isEmpty);
  });

  test('pins and unpins', () async {
    await repository.save(record('a'));

    expect((await repository.setPinned('a', pinned: true))!.pinned, isTrue);
    expect((await repository.get('a'))!.pinned, isTrue);
    expect((await repository.setPinned('a', pinned: false))!.pinned, isFalse);
    expect(await repository.setPinned('b', pinned: true), isNull);
  });
}

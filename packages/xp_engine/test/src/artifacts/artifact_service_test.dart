import 'dart:convert';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  late InMemoryArtifactRepository repository;
  late InMemoryArtifactStore store;
  late InMemoryJobRepository jobs;
  late ArtifactService service;

  final record = ArtifactRecord(
    id: 'art_1',
    jobId: 'job_1',
    kind: ArtifactKind.apk,
    path: 'job_1/dev.apk',
    size: 3,
    sha256: 'a' * 64,
    createdAt: DateTime.utc(2026),
  );

  setUp(() async {
    repository = InMemoryArtifactRepository();
    store = InMemoryArtifactStore();
    jobs = InMemoryJobRepository();
    service = ArtifactService(repository: repository, store: store, jobs: jobs);
    await jobs.create(
      JobRecord(
        id: 'job_1',
        workflowVersionId: 'wfv_1',
        projectId: 'prj_1',
        state: JobState.succeeded,
        createdAt: DateTime.utc(2026),
      ),
      const [],
    );
    await repository.save(record);
  });

  test('lists the artifacts of a job, also when it has none', () async {
    expect(await service.forJob('job_1'), [record]);
    await jobs.create(
      JobRecord(
        id: 'job_2',
        workflowVersionId: 'wfv_1',
        projectId: 'prj_1',
        state: JobState.queued,
        createdAt: DateTime.utc(2026),
      ),
      const [],
    );
    expect(await service.forJob('job_2'), isEmpty);
  });

  test('does not list the artifacts of a job that does not exist', () async {
    await expectLater(
      service.forJob('job_9'),
      throwsA(isA<JobNotFoundException>()),
    );
  });

  test('reads one artifact', () async {
    expect(await service.get('art_1'), record);
    await expectLater(
      service.get('art_9'),
      throwsA(isA<ArtifactNotFoundException>()),
    );
  });

  test('downloads the bytes with the record', () async {
    store.files['job_1/dev.apk'] = utf8.encode('abc');

    final download = await service.download('art_1');

    expect(download.record, record);
    expect(
      utf8.decode(await download.content.expand((c) => c).toList()),
      'abc',
    );
  });

  test('does not download an artifact that is not there', () async {
    await expectLater(
      service.download('art_9'),
      throwsA(isA<ArtifactNotFoundException>()),
    );
  });

  test('does not download a file that left the store', () async {
    await expectLater(
      service.download('art_1'),
      throwsA(
        isA<ArtifactNotFoundException>().having(
          (e) => e.message,
          'message',
          contains('no longer in the artifact store'),
        ),
      ),
    );
  });

  test('pins and unpins', () async {
    expect((await service.pin('art_1')).pinned, isTrue);
    expect((await service.pin('art_1')).pinned, isTrue);
    expect((await service.unpin('art_1')).pinned, isFalse);
    await expectLater(
      service.pin('art_9'),
      throwsA(isA<ArtifactNotFoundException>()),
    );
    await expectLater(
      service.unpin('art_9'),
      throwsA(isA<ArtifactNotFoundException>()),
    );
  });

  test('exceptions describe themselves', () {
    expect(
      const ArtifactNotFoundException('x').toString(),
      'ArtifactNotFoundException: x',
    );
  });
}

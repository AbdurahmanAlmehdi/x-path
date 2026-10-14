import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  late InMemoryArtifactStore store;
  late InMemoryArtifactRepository repository;
  late RunnerArtifacts artifacts;
  var holding = true;

  final bytes = utf8.encode('the contents of an apk');
  final digest = sha256.convert(bytes).toString();

  Future<ArtifactRecord> upload({
    Stream<List<int>>? content,
    String? sha,
    int? size,
    String name = 'dev-1.0.0+7.apk',
  }) => artifacts.upload(
    runnerId: 'rnr_1',
    jobId: 'job_1',
    leaseId: 'lse_1',
    kind: ArtifactKind.apk,
    name: name,
    content: content ?? Stream.value(bytes),
    sha256: sha ?? digest,
    size: size ?? bytes.length,
  );

  setUp(() {
    holding = true;
    store = InMemoryArtifactStore();
    repository = InMemoryArtifactRepository();
    artifacts = RunnerArtifacts(
      recorder: ArtifactRecorder(
        store: store,
        repository: repository,
        clock: ManualClock(DateTime.utc(2026, 10, 14, 9)),
      ),
      holdsLease: (runnerId, jobId, leaseId) =>
          holding && (runnerId, jobId, leaseId) == ('rnr_1', 'job_1', 'lse_1'),
    );
  });

  test('stores a file whose digest and size are what was declared', () async {
    final record = await upload(
      content: Stream.fromIterable([bytes.sublist(0, 5), bytes.sublist(5)]),
    );

    expect(record.jobId, 'job_1');
    expect(record.kind, ArtifactKind.apk);
    expect(record.name, 'dev-1.0.0+7.apk');
    expect(record.size, bytes.length);
    expect(record.sha256, digest);
    expect(store.files['job_1/dev-1.0.0+7.apk'], bytes);
    expect(await repository.forJob('job_1'), [record]);
  });

  test('takes the digest in any case', () async {
    final record = await upload(sha: digest.toUpperCase());

    expect(record.sha256, digest);
  });

  test('stores an empty file', () async {
    final record = await upload(
      content: const Stream.empty(),
      sha: sha256.convert(const []).toString(),
      size: 0,
    );

    expect(record.size, 0);
    expect(store.files['job_1/dev-1.0.0+7.apk'], isEmpty);
  });

  test('rejects a file whose digest is not the one declared', () async {
    await expectLater(
      upload(sha: sha256.convert([1]).toString()),
      throwsA(
        isA<ArtifactChecksumException>().having(
          (e) => e.message,
          'message',
          allOf(contains(digest), contains('declared')),
        ),
      ),
    );

    expect(store.files, isEmpty);
    expect(await repository.forJob('job_1'), isEmpty);
  });

  test('rejects a file that is shorter or longer than declared', () async {
    await expectLater(
      upload(size: bytes.length + 1),
      throwsA(
        isA<ArtifactChecksumException>().having(
          (e) => e.message,
          'message',
          contains('${bytes.length} bytes, not the ${bytes.length + 1}'),
        ),
      ),
    );
    await expectLater(
      upload(size: bytes.length - 1),
      throwsA(
        isA<ArtifactChecksumException>().having(
          (e) => e.message,
          'message',
          contains('longer than the ${bytes.length - 1} bytes'),
        ),
      ),
    );
    await expectLater(
      upload(content: Stream.fromIterable([bytes, bytes]), size: bytes.length),
      throwsA(isA<ArtifactChecksumException>()),
    );

    expect(store.files, isEmpty);
    expect(await repository.forJob('job_1'), isEmpty);
  });

  test('a bad upload leaves the file that was there', () async {
    final good = await upload();

    await expectLater(
      upload(content: Stream.value(utf8.encode('something else'))),
      throwsA(isA<ArtifactChecksumException>()),
    );

    expect(store.files['job_1/dev-1.0.0+7.apk'], bytes);
    expect(await repository.get(good.id), good);
  });

  test('a stream that breaks leaves no trace', () async {
    await expectLater(
      upload(
        content: Stream<List<int>>.multi((controller) {
          controller
            ..add(bytes.sublist(0, 3))
            ..addError(StateError('connection lost'));
        }),
      ),
      throwsStateError,
    );

    expect(store.files, isEmpty);
  });

  test('replaces the file of the same name, as the recorder does', () async {
    final first = await upload();
    final second = await upload();

    expect(second.id, first.id);
    expect(await repository.forJob('job_1'), hasLength(1));
  });

  test('is for the runner that holds the lease', () async {
    holding = false;

    await expectLater(
      upload(),
      throwsA(
        isA<RunnerLeaseException>().having(
          (e) => e.message,
          'message',
          contains('rnr_1 does not hold lease lse_1 of job job_1'),
        ),
      ),
    );

    expect(store.files, isEmpty);
  });

  test('wants a plain name', () async {
    for (final name in [
      '',
      '.',
      '..',
      '../x',
      'a/b',
      '.hidden',
      r'a\b',
      'a b',
    ]) {
      await expectLater(
        upload(name: name),
        throwsA(isA<RunnerInvalidException>()),
        reason: name,
      );
    }
    expect(store.files, isEmpty);
  });

  test('wants a digest and a size that make sense', () async {
    for (final sha in ['', 'abc', 'g' * 64, '${digest}0']) {
      await expectLater(
        upload(sha: sha),
        throwsA(isA<RunnerInvalidException>()),
        reason: sha,
      );
    }
    await expectLater(upload(size: -1), throwsA(isA<RunnerInvalidException>()));
  });
}

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:xp/src/runner/job/uploading_artifacts.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_client/xp_client.dart';
import 'package:xp_engine/xp_engine.dart';

class _Upload {
  const new({
    required this.jobId,
    required this.leaseId,
    required this.name,
    required this.kind,
    required this.bytes,
    required this.size,
    required this.sha256,
  });

  final String jobId;
  final String leaseId;
  final String name;
  final ArtifactKind kind;
  final List<int> bytes;
  final int size;
  final String sha256;
}

void main() {
  late InMemoryArtifactStore store;
  late List<_Upload> uploads;
  late Exception? failure;
  late UploadingArtifactRepository repository;
  late ArtifactRecorder recorder;

  setUp(() {
    store = InMemoryArtifactStore();
    uploads = [];
    failure = null;
    repository = UploadingArtifactRepository(
      store: store,
      leaseId: 'lse_1',
      upload:
          ({
            required jobId,
            required leaseId,
            required name,
            required kind,
            required content,
            required size,
            required sha256,
          }) async {
            if (failure case final error?) throw error;
            final bytes = <int>[];
            await content().forEach(bytes.addAll);
            uploads.add(
              _Upload(
                jobId: jobId,
                leaseId: leaseId,
                name: name,
                kind: kind,
                bytes: bytes,
                size: size,
                sha256: sha256,
              ),
            );
          },
    );
    recorder = ArtifactRecorder(
      store: store,
      repository: repository,
      clock: ManualClock(DateTime.utc(2026, 10, 14)),
    );
  });

  test('uploads a file as it is recorded, with its size and SHA-256', () async {
    final bytes = utf8.encode('apk bytes');

    final record = await recorder.record(
      jobId: 'job_1',
      kind: ArtifactKind.apk,
      name: 'dev-1.0.0+1.apk',
      content: Stream.value(bytes),
    );

    final upload = uploads.single;
    expect(upload.jobId, 'job_1');
    expect(upload.leaseId, 'lse_1');
    expect(upload.name, 'dev-1.0.0+1.apk');
    expect(upload.kind, ArtifactKind.apk);
    expect(upload.bytes, bytes);
    expect(upload.size, bytes.length);
    expect(upload.sha256, sha256.convert(bytes).toString());
    expect(upload.sha256, record.sha256);
    expect(
      await repository.findByPath('job_1', 'job_1/dev-1.0.0+1.apk'),
      record,
    );
  });

  test('keeps nothing for a file that could not be uploaded', () async {
    failure = const ApiException('Lease lost.', statusCode: 409);

    await expectLater(
      recorder.record(
        jobId: 'job_1',
        kind: ArtifactKind.apk,
        name: 'a.apk',
        content: Stream.value([1]),
      ),
      throwsA(isA<ApiException>()),
    );

    expect(await repository.forJob('job_1'), isEmpty);
  });

  group('retrying', () {
    late List<Duration> waits;
    late int calls;

    ArtifactUpload flaky(int failures, Exception error) {
      calls = 0;
      return ({
        required jobId,
        required leaseId,
        required name,
        required kind,
        required content,
        required size,
        required sha256,
      }) async {
        if (calls++ < failures) throw error;
      };
    }

    Future<void> run(ArtifactUpload upload) =>
        retrying(upload, wait: (duration) async => waits.add(duration))(
          jobId: 'job_1',
          leaseId: 'lse_1',
          name: 'a.apk',
          kind: ArtifactKind.apk,
          content: Stream<List<int>>.empty,
          size: 0,
          sha256: '',
        );

    setUp(() => waits = []);

    test('tries again when the connection fails', () async {
      await run(flaky(2, const ConnectionException('reset')));

      expect(calls, 3);
      expect(waits, [const Duration(seconds: 2), const Duration(seconds: 8)]);
    });

    test('gives up after the last delay', () async {
      await expectLater(
        run(flaky(5, const ConnectionException('reset'))),
        throwsA(isA<ConnectionException>()),
      );

      expect(calls, 3);
    });

    test('does not try again when the engine refuses', () async {
      await expectLater(
        run(flaky(1, const ApiException('Wrong digest.', statusCode: 400))),
        throwsA(isA<ApiException>()),
      );

      expect(calls, 1);
      expect(waits, isEmpty);
    });

    test('uploads at once when nothing fails', () async {
      await run(flaky(0, const ConnectionException('never')));

      expect(calls, 1);
      expect(waits, isEmpty);
    });
  });
}

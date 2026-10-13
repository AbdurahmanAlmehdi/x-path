import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../helpers/test_engine.dart';

void main() {
  late TestEngine engine;
  late Job job;

  setUp(() async {
    engine = await TestEngine.start();
    job = await engine.createJob(['a']);
  });
  tearDown(() => engine.close());

  String errorCode(RawResponse response) =>
      (response.json['error']! as Map<String, dynamic>)['code']! as String;

  group('GET /jobs/{id}/artifacts', () {
    test('lists the artifacts of the job without their place', () async {
      final apk = await engine.addArtifact(job.id);
      engine.clock.advance(const Duration(minutes: 1));
      final manifest = await engine.addArtifact(
        job.id,
        name: 'manifest.json',
        kind: ArtifactKind.manifest,
        content: '{}',
      );

      final response = await engine.request('/jobs/${job.id}/artifacts');

      expect(response.statusCode, 200);
      final listed = ArtifactsResponse.fromJson(response.json).artifacts;
      expect(listed, [apk.toArtifact(), manifest.toArtifact()]);
      expect(response.body, isNot(contains(apk.path)));
    });

    test('is empty for a job that produced nothing', () async {
      final response = await engine.request('/jobs/${job.id}/artifacts');

      expect(response.statusCode, 200);
      expect(response.json, {'artifacts': <Object?>[]});
    });

    test('does not list the artifacts of other jobs', () async {
      final other = await engine.createJob(['b']);
      await engine.addArtifact(other.id);

      final response = await engine.request('/jobs/${job.id}/artifacts');

      expect(ArtifactsResponse.fromJson(response.json).artifacts, isEmpty);
    });

    test('404 for a job that does not exist', () async {
      final response = await engine.request('/jobs/job_nope/artifacts');

      expect(response.statusCode, 404);
      expect(errorCode(response), 'not_found');
    });

    test('401 without a token', () async {
      final response = await engine.request(
        '/jobs/${job.id}/artifacts',
        token: '',
      );

      expect(response.statusCode, 401);
    });
  });

  group('GET /artifacts/{id}', () {
    test('returns the metadata', () async {
      final apk = await engine.addArtifact(job.id);

      final response = await engine.request('/artifacts/${apk.id}');

      expect(response.statusCode, 200);
      expect(Artifact.fromJson(response.json), apk.toArtifact());
    });

    test('404 for an artifact that does not exist', () async {
      final response = await engine.request('/artifacts/art_nope');

      expect(response.statusCode, 404);
      expect(errorCode(response), 'not_found');
    });
  });

  group('GET /artifacts/{id}/download', () {
    test('streams the file with its length and SHA-256', () async {
      final apk = await engine.addArtifact(job.id);

      final response = await engine.download('/artifacts/${apk.id}/download');

      expect(response.statusCode, 200);
      expect(response.text, 'apk bytes');
      expect(response.headers.contentLength, 9);
      expect(
        response.headers.value('x-content-sha256'),
        sha256OfBytes(utf8.encode('apk bytes')),
      );
      expect(
        response.headers.contentType?.mimeType,
        'application/octet-stream',
      );
      expect(
        response.headers.value('content-disposition'),
        'attachment; filename="dev-1.0.0+1.apk"',
      );
    });

    test('streams a file that is larger than one chunk', () async {
      final big = 'x' * (1 << 20);
      final apk = await engine.addArtifact(job.id, content: big);

      final response = await engine.download('/artifacts/${apk.id}/download');

      expect(response.bytes, hasLength(big.length));
      expect(response.headers.contentLength, big.length);
    });

    test('404 for an artifact that does not exist', () async {
      final response = await engine.download('/artifacts/art_nope/download');

      expect(response.statusCode, 404);
    });

    test('404 for a file that left the store', () async {
      final apk = await engine.addArtifact(job.id);
      engine.artifactStore.files.clear();

      final response = await engine.request('/artifacts/${apk.id}/download');

      expect(response.statusCode, 404);
      expect(response.json['error'], containsPair('code', 'not_found'));
    });

    test('401 without a token', () async {
      final apk = await engine.addArtifact(job.id);

      final response = await engine.download(
        '/artifacts/${apk.id}/download',
        token: '',
      );

      expect(response.statusCode, HttpStatus.unauthorized);
    });
  });

  group('pin and unpin', () {
    test('pin keeps the artifact, and pinning again changes nothing', () async {
      final apk = await engine.addArtifact(job.id);

      final first = await engine.request(
        '/artifacts/${apk.id}/pin',
        method: 'POST',
      );
      final second = await engine.request(
        '/artifacts/${apk.id}/pin',
        method: 'POST',
      );

      expect(first.statusCode, 200);
      expect(Artifact.fromJson(first.json).pinned, isTrue);
      expect(Artifact.fromJson(second.json).pinned, isTrue);
      expect((await engine.artifactRepository.get(apk.id))!.pinned, isTrue);
    });

    test('unpin lets go of the artifact', () async {
      final apk = await engine.addArtifact(job.id);
      await engine.request('/artifacts/${apk.id}/pin', method: 'POST');

      final response = await engine.request(
        '/artifacts/${apk.id}/unpin',
        method: 'POST',
      );

      expect(response.statusCode, 200);
      expect(Artifact.fromJson(response.json).pinned, isFalse);
      expect((await engine.artifactRepository.get(apk.id))!.pinned, isFalse);
    });

    test('404 for an artifact that does not exist', () async {
      for (final action in ['pin', 'unpin']) {
        final response = await engine.request(
          '/artifacts/art_nope/$action',
          method: 'POST',
        );

        expect(response.statusCode, 404, reason: action);
      }
    });
  });
}

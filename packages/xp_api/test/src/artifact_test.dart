import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';

void main() {
  final created = DateTime.utc(2026, 10, 13, 9);

  group('ArtifactKind', () {
    test('uses snake_case on the wire', () {
      expect(ArtifactKind.shorebirdSymbols.wire, 'shorebird_symbols');
      expect(ArtifactKind.apk.wire, 'apk');
    });

    test('has the kinds the artifact table allows', () {
      expect(ArtifactKind.values.map((kind) => kind.wire), [
        'ipa',
        'aab',
        'apk',
        'mapping',
        'dsym',
        'manifest',
        'shorebird_symbols',
      ]);
    });
  });

  group('Artifact', () {
    final artifact = Artifact(
      id: 'art_1',
      jobId: 'job_1',
      kind: ArtifactKind.apk,
      name: 'dev-1.0.0+7.apk',
      size: 1024,
      sha256: 'a' * 64,
      pinned: true,
      createdAt: created,
    );

    test('serializes every field', () {
      expect(artifact.toJson(), {
        'id': 'art_1',
        'jobId': 'job_1',
        'kind': 'apk',
        'name': 'dev-1.0.0+7.apk',
        'size': 1024,
        'sha256': 'a' * 64,
        'pinned': true,
        'createdAt': '2026-10-13T09:00:00.000Z',
      });
    });

    test('round-trips through JSON', () {
      expect(Artifact.fromJson(artifact.toJson()), artifact);
    });
  });

  test('ArtifactsResponse lists the artifacts inline', () {
    final response = ArtifactsResponse([
      Artifact(
        id: 'art_1',
        jobId: 'job_1',
        kind: ArtifactKind.manifest,
        name: 'manifest.json',
        size: 10,
        sha256: 'b' * 64,
        pinned: false,
        createdAt: created,
      ),
    ]);

    final json = response.toJson();

    expect((json['artifacts']! as List).single, isA<Map<String, dynamic>>());
    expect(ArtifactsResponse.fromJson(json), response);
  });
}

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  final created = DateTime.utc(2026, 10, 13, 9);
  final record = ArtifactRecord(
    id: 'art_1',
    jobId: 'job_1',
    kind: ArtifactKind.apk,
    path: 'job_1/dev-1.0.0+7.apk',
    size: 12,
    sha256: 'a' * 64,
    createdAt: created,
  );

  test('names the file after the last part of its path', () {
    expect(record.name, 'dev-1.0.0+7.apk');
  });

  test('is not pinned by default and can be pinned', () {
    expect(record.pinned, isFalse);
    expect(record.withPinned(pinned: true).pinned, isTrue);
    expect(record.withPinned(pinned: true).path, record.path);
  });

  test('shows clients everything but the place in the store', () {
    expect(
      record.toArtifact(),
      Artifact(
        id: 'art_1',
        jobId: 'job_1',
        kind: ArtifactKind.apk,
        name: 'dev-1.0.0+7.apk',
        size: 12,
        sha256: 'a' * 64,
        pinned: false,
        createdAt: created,
      ),
    );
  });

  test('summarizes into what a step reports', () {
    final summary = ArtifactSummary.of(record);

    expect(summary.toJson(), {
      'id': 'art_1',
      'kind': 'apk',
      'name': 'dev-1.0.0+7.apk',
      'size': 12,
      'sha256': 'a' * 64,
    });
  });
}

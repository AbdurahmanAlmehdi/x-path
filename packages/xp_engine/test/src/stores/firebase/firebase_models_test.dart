import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  group('FirebaseUploadResult', () {
    test('is read from the wire', () {
      expect(
        FirebaseUploadResult.fromWire('RELEASE_CREATED'),
        FirebaseUploadResult.created,
      );
      expect(
        FirebaseUploadResult.fromWire('RELEASE_UPDATED'),
        FirebaseUploadResult.updated,
      );
      expect(
        FirebaseUploadResult.fromWire('RELEASE_UNMODIFIED'),
        FirebaseUploadResult.unmodified,
      );
    });

    test('is unknown for anything else', () {
      expect(FirebaseUploadResult.fromWire(null), FirebaseUploadResult.unknown);
      expect(
        FirebaseUploadResult.fromWire('UPLOAD_RELEASE_RESULT_UNSPECIFIED'),
        FirebaseUploadResult.unknown,
      );
      expect(FirebaseUploadResult.fromWire(''), FirebaseUploadResult.unknown);
    });
  });

  test('releases and operations compare by value', () {
    expect(
      const FirebaseRelease(name: 'r', buildVersion: '1'),
      const FirebaseRelease(name: 'r', buildVersion: '1'),
    );
    expect(
      const FirebaseOperation(name: 'o', done: true),
      const FirebaseOperation(name: 'o', done: true),
    );
    expect(
      const FirebaseRelease(name: 'r'),
      isNot(const FirebaseRelease(name: 'r', testingUri: 'u')),
    );
    expect(
      const FirebaseOperation(name: 'o'),
      isNot(const FirebaseOperation(name: 'o', done: true)),
    );
  });
}

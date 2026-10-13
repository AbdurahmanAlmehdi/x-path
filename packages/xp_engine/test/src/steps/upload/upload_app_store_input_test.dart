import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

Map<String, dynamic> _json({
  String artifactName = 'prod-5.4.1+3283.ipa',
  String version = '5.4.1+3283',
  Map<String, dynamic>? auth,
}) => {
  'artifactName': artifactName,
  'bundleId': 'com.mataa.app',
  'appleAppId': '1234567890',
  'version': version,
  'auth': auth ?? {'type': 'apiKey', 'keySecret': 'asc.prod'},
};

void main() {
  group('UploadAppStoreInput', () {
    test('round trips with an API key', () {
      final input = UploadAppStoreInput.fromJson(_json());

      expect(input.auth, const ApiKeyUploadAuth('asc.prod'));
      expect(input.build, '3283');
      expect(input.version.name.toString(), '5.4.1');
      expect(UploadAppStoreInput.fromJson(input.toJson()), input);
      expect(input.toJson(), _json());
    });

    test('round trips with an Apple ID', () {
      final json = _json(
        auth: {
          'type': 'appleId',
          'appleId': 'dev@example.com',
          'passwordSecret': 'apple.password',
        },
      );

      final input = UploadAppStoreInput.fromJson(json);

      expect(
        input.auth,
        const AppleIdUploadAuth(
          appleId: 'dev@example.com',
          passwordSecret: 'apple.password',
        ),
      );
      expect(input.toJson(), json);
    });

    test('needs a build number', () {
      expect(
        () => UploadAppStoreInput.fromJson(_json(version: '5.4.1')),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('build number'),
          ),
        ),
      );
    });

    test('needs a plain file name', () {
      expect(
        () => UploadAppStoreInput.fromJson(_json(artifactName: '../a.ipa')),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => UploadAppStoreInput.fromJson(_json(artifactName: r'a\b.ipa')),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects an unknown auth type and missing fields', () {
      expect(
        () => UploadAppStoreInput.fromJson(_json(auth: {'type': 'basic'})),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => UploadAppStoreInput.fromJson(_json(auth: {'type': 'apiKey'})),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => UploadAppStoreInput.fromJson(
          _json(auth: {'type': 'appleId', 'appleId': 'a@b.c'}),
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => UploadAppStoreInput.fromJson({..._json()}..remove('bundleId')),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('UploadAppStoreResult', () {
    test('stores only what it has', () {
      expect(const UploadAppStoreResult().toJson(), {
        'alreadyUploaded': false,
        'confirmed': false,
      });
      expect(
        const UploadAppStoreResult(
          alreadyUploaded: true,
          confirmed: true,
          deliveryId: 'd',
          buildId: 'b',
          processingState: 'VALID',
        ).toJson(),
        {
          'alreadyUploaded': true,
          'confirmed': true,
          'deliveryId': 'd',
          'buildId': 'b',
          'processingState': 'VALID',
        },
      );
    });

    test('compares by value', () {
      expect(const UploadAppStoreResult(), const UploadAppStoreResult());
    });
  });
}

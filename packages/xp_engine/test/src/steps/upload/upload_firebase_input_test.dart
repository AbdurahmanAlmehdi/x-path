import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

const _appId = '1:684690133351:android:b434734f585770367c1fc2';

Map<String, dynamic> _json([Map<String, dynamic> overrides = const {}]) => {
  'artifactName': 'dev-1.2.3+45.apk',
  'appId': _appId,
  'version': '1.2.3+45',
  'serviceAccountSecret': 'credential.crd_1',
  ...overrides,
};

void main() {
  group('UploadFirebaseInput', () {
    test('reads the required fields and defaults the rest', () {
      final input = UploadFirebaseInput.fromJson(_json());

      expect(input.artifactName, 'dev-1.2.3+45.apk');
      expect(input.version, AppVersion.parse('1.2.3+45'));
      expect(input.testerEmails, isEmpty);
      expect(input.groupAliases, isEmpty);
      expect(input.releaseNotes, isNull);
      expect(input.distributes, isFalse);
      expect(input.kind, ArtifactKind.apk);
    });

    test('derives the project number and the app name from the app id', () {
      final input = UploadFirebaseInput.fromJson(_json());

      expect(input.projectNumber, '684690133351');
      expect(input.appName, 'projects/684690133351/apps/$_appId');
    });

    test('round-trips with testers, groups and notes', () {
      final input = UploadFirebaseInput.fromJson(
        _json({
          'testerEmails': ['a@example.com'],
          'groupAliases': ['qa-team'],
          'releaseNotes': 'Fixes',
        }),
      );

      expect(input.distributes, isTrue);
      expect(UploadFirebaseInput.fromJson(input.toJson()), input);
      expect(input.toJson()['testerEmails'], ['a@example.com']);
    });

    test('leaves out what is empty when stored', () {
      expect(UploadFirebaseInput.fromJson(_json()).toJson().keys, [
        'artifactName',
        'appId',
        'version',
        'serviceAccountSecret',
      ]);
    });

    test('knows the kind of artifact by the extension', () {
      expect(UploadFirebaseInput.kindOf('a.APK'), ArtifactKind.apk);
      expect(UploadFirebaseInput.kindOf('a.aab'), ArtifactKind.aab);
      expect(UploadFirebaseInput.kindOf('a.ipa'), ArtifactKind.ipa);
      expect(UploadFirebaseInput.kindOf('a.zip'), isNull);
    });

    test('refuses what it cannot use', () {
      for (final overrides in <Map<String, dynamic>>[
        {'version': '1.2.3'},
        {'version': 'one'},
        {'artifactName': 'dir/dev.apk'},
        {'artifactName': r'dir\dev.apk'},
        {'artifactName': 'dev.zip'},
        {'appId': 'com.example.app'},
        {'appId': '1:abc:android:ff'},
        {'serviceAccountSecret': ''},
        {
          'testerEmails': ['nope'],
        },
        {
          'testerEmails': [1],
        },
        {
          'groupAliases': ['two words'],
        },
        {'releaseNotes': 3},
        {
          'testerEmails': [for (var i = 0; i < 1000; i++) 'u$i@example.com'],
        },
      ]) {
        expect(
          () => UploadFirebaseInput.fromJson(_json(overrides)),
          throwsFormatException,
          reason: '$overrides',
        );
      }
    });
  });

  group('UploadFirebaseResult', () {
    test('stores what is known', () {
      const result = UploadFirebaseResult(
        releaseName: 'projects/1/apps/a/releases/r',
        displayVersion: '1.2.3',
        buildVersion: '45',
        result: FirebaseUploadResult.created,
        distributed: true,
        consoleUri: 'https://console',
        testingUri: 'https://testing',
      );

      expect(result.toJson(), {
        'releaseName': 'projects/1/apps/a/releases/r',
        'displayVersion': '1.2.3',
        'buildVersion': '45',
        'result': 'RELEASE_CREATED',
        'alreadyUploaded': false,
        'distributed': true,
        'consoleUri': 'https://console',
        'testingUri': 'https://testing',
      });
    });

    test('leaves out what is unknown', () {
      expect(const UploadFirebaseResult(releaseName: 'r').toJson(), {
        'releaseName': 'r',
        'alreadyUploaded': false,
        'distributed': false,
      });
    });
  });
}

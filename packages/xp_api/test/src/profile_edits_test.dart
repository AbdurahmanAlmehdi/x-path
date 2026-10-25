import 'package:json_annotation/json_annotation.dart';
import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';

void main() {
  group('ProfileEdits', () {
    const edits = ProfileEdits(
      defaultBaseBranch: 'dev',
      apps: [
        AppEdit(
          path: '.',
          storeCountry: 'ly',
          flavors: [
            FlavorEdit(
              name: 'prod',
              prod: true,
              shorebird: false,
              entrypoint: 'lib/main_prod.dart',
              iosBundleId: 'com.a',
              androidAppId: 'com.b',
              versionFiles: ['pubspec.yaml'],
              firebaseAppId: {'android': '1:1:android:a'},
              appleAppId: '123',
            ),
          ],
        ),
      ],
    );

    test('round-trips through JSON', () {
      expect(ProfileEdits.fromJson(edits.toJson()), edits);
    });

    test('reads an empty object as no edits', () {
      expect(ProfileEdits.fromJson(const {}).isEmpty, isTrue);
      expect(edits.isEmpty, isFalse);
      expect(const ProfileEdits(defaultBaseBranch: 'x').isEmpty, isFalse);
    });

    test('merge lets the newer edit win field by field', () {
      const newer = ProfileEdits(
        apps: [
          AppEdit(
            path: '.',
            flavors: [
              FlavorEdit(name: 'prod', prod: false),
              FlavorEdit(name: 'dev', prod: true),
            ],
          ),
          AppEdit(path: 'apps/b', storeCountry: 'us'),
        ],
      );

      final merged = edits.merge(newer);

      expect(merged.defaultBaseBranch, 'dev');
      expect(merged.apps.map((a) => a.path), ['.', 'apps/b']);
      final root = merged.apps.first;
      expect(root.storeCountry, 'ly');
      final prod = root.flavors.firstWhere((f) => f.name == 'prod');
      expect(prod.prod, isFalse);
      expect(prod.entrypoint, 'lib/main_prod.dart');
      expect(prod.shorebird, isFalse);
      expect(prod.iosBundleId, 'com.a');
      expect(prod.androidAppId, 'com.b');
      expect(prod.versionFiles, ['pubspec.yaml']);
      expect(prod.firebaseAppId, {'android': '1:1:android:a'});
      expect(prod.appleAppId, '123');
      expect(root.flavors.map((f) => f.name), ['prod', 'dev']);
      final dev = root.flavors.firstWhere((f) => f.name == 'dev');
      expect(dev.firebaseAppId, isNull);
    });

    test('merge adds the Firebase ids of the newer platforms', () {
      const older = FlavorEdit(
        name: 'dev',
        firebaseAppId: {'android': '1:1:android:a', 'ios': '1:1:ios:b'},
      );

      final merged = older.merge(
        const FlavorEdit(
          name: 'dev',
          firebaseAppId: {'ios': ''},
          appleAppId: '9',
        ),
      );

      expect(merged.firebaseAppId, {'android': '1:1:android:a', 'ios': ''});
      expect(merged.appleAppId, '9');
      expect(
        const FlavorEdit(name: 'x').merge(const FlavorEdit(name: 'x')),
        const FlavorEdit(name: 'x'),
      );
    });

    test('merge takes a newer base branch and store country', () {
      final merged = edits.merge(
        const ProfileEdits(
          defaultBaseBranch: 'main',
          apps: [AppEdit(path: '.', storeCountry: 'us')],
        ),
      );

      expect(merged.defaultBaseBranch, 'main');
      expect(merged.apps.single.storeCountry, 'us');
    });
  });

  group('reading edits of the wrong shape', () {
    test('fails with a CheckedFromJsonException at any depth', () {
      for (final json in <Map<String, dynamic>>[
        {'defaultBaseBranch': 1},
        {'apps': 'x'},
        {
          'apps': [
            {'path': '.', 'storeCountry': 1},
          ],
        },
        {
          'apps': [
            {
              'path': '.',
              'flavors': [
                {'name': 'dev', 'prod': 'yes'},
              ],
            },
          ],
        },
        {
          'apps': [
            {
              'path': '.',
              'flavors': [<String, dynamic>{}],
            },
          ],
        },
      ]) {
        expect(
          () => ProfileEdits.fromJson(json),
          throwsA(isA<CheckedFromJsonException>()),
          reason: '$json',
        );
      }
    });
  });
}

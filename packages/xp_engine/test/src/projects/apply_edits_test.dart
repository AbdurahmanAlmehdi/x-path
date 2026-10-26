import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  const profile = ProjectProfile(
    apps: [
      AppProfile(
        name: 'one',
        path: '.',
        flavors: [
          FlavorProfile(name: 'dev', entrypoint: 'lib/main_dev.dart'),
          FlavorProfile(name: 'prod', entrypoint: 'lib/main_prod.dart'),
        ],
      ),
      AppProfile(name: 'two', path: 'apps/two'),
    ],
  );

  group('applyEdits', () {
    test('leaves the profile alone without edits', () {
      expect(applyEdits(profile, const ProfileEdits()), same(profile));
    });

    test('changes only what is edited', () {
      final edited = applyEdits(
        profile,
        const ProfileEdits(
          apps: [
            AppEdit(
              path: '.',
              storeCountry: 'ly',
              flavors: [
                FlavorEdit(
                  name: 'prod',
                  prod: true,
                  shorebird: true,
                  entrypoint: 'lib/main.dart',
                  iosBundleId: 'com.ios',
                  androidAppId: 'com.android',
                  versionFiles: ['pubspec.yaml'],
                ),
              ],
            ),
          ],
        ),
      );

      final app = edited.apps.first;
      expect(app.storeCountry, 'ly');
      expect(app.iosLinux, isTrue);
      expect(app.flavors.first, profile.apps.first.flavors.first);
      final prod = app.flavors.last;
      expect(prod.prod, isTrue);
      expect(prod.shorebird, isTrue);
      expect(prod.entrypoint, 'lib/main.dart');
      expect(prod.iosBundleId, 'com.ios');
      expect(prod.androidAppId, 'com.android');
      expect(prod.versionFiles, ['pubspec.yaml']);
      expect(edited.apps.last, profile.apps.last);
    });

    test('turns Linux iOS builds off and on again', () {
      ProfileEdits turn({required bool on}) => ProfileEdits(
        apps: [AppEdit(path: 'apps/two', iosLinux: on)],
      );

      final off = applyEdits(profile, turn(on: false));
      expect(off.apps.last.iosLinux, isFalse);
      expect(off.apps.first, profile.apps.first);
      expect(applyEdits(off, turn(on: true)).apps.last.iosLinux, isTrue);
    });

    test('sets, keeps and removes the store ids', () {
      const scanned = ProjectProfile(
        apps: [
          AppProfile(
            name: 'one',
            path: '.',
            flavors: [
              FlavorProfile(
                name: 'dev',
                entrypoint: 'lib/main_dev.dart',
                firebaseAppId: {'android': '1:1:android:a'},
                appleAppId: '7',
              ),
            ],
          ),
        ],
      );
      FlavorProfile edit(FlavorEdit change) => applyEdits(
        scanned,
        ProfileEdits(
          apps: [
            AppEdit(path: '.', flavors: [change]),
          ],
        ),
      ).apps.single.flavors.single;

      final added = edit(
        const FlavorEdit(
          name: 'dev',
          firebaseAppId: {'ios': '1:1:ios:b'},
          appleAppId: '9',
        ),
      );
      expect(added.firebaseAppId, {
        'android': '1:1:android:a',
        'ios': '1:1:ios:b',
      });
      expect(added.appleAppId, '9');

      final kept = edit(const FlavorEdit(name: 'dev', prod: true));
      expect(kept.firebaseAppId, {'android': '1:1:android:a'});
      expect(kept.appleAppId, '7');

      final removed = edit(
        const FlavorEdit(
          name: 'dev',
          firebaseAppId: {'android': ''},
          appleAppId: '',
        ),
      );
      expect(removed.firebaseAppId, isNull);
      expect(removed.appleAppId, isNull);
    });

    test('ignores edits of apps and flavors that are gone', () {
      final edited = applyEdits(
        profile,
        const ProfileEdits(
          apps: [
            AppEdit(path: 'apps/gone', storeCountry: 'de'),
            AppEdit(
              path: '.',
              flavors: [FlavorEdit(name: 'gone', prod: true)],
            ),
          ],
        ),
      );

      expect(edited, profile);
    });
  });

  group('validateEdits', () {
    void expectInvalid(ProfileEdits edits, Pattern message) {
      expect(
        () => validateEdits(profile, edits),
        throwsA(
          isA<ProjectInvalidException>().having(
            (e) => e.message,
            'message',
            contains(message),
          ),
        ),
      );
    }

    test('accepts edits of what exists and lower-cases the country', () {
      final valid = validateEdits(
        profile,
        const ProfileEdits(
          defaultBaseBranch: ' dev ',
          apps: [
            AppEdit(
              path: '.',
              storeCountry: 'LY',
              flavors: [
                FlavorEdit(
                  name: 'dev',
                  entrypoint: 'lib/main.dart',
                  versionFiles: ['pubspec.yaml', 'ios/Runner/Info.plist'],
                ),
              ],
            ),
            AppEdit(path: 'apps/two', iosLinux: false),
          ],
        ),
      );

      expect(valid.defaultBaseBranch, 'dev');
      expect(valid.apps.first.iosLinux, isNull);
      expect(valid.apps.last.iosLinux, isFalse);
      expect(valid.apps.first.storeCountry, 'ly');
      expect(valid.apps.first.flavors.single.name, 'dev');
      expect(valid.apps.last.storeCountry, isNull);
    });

    test('accepts no edits', () {
      expect(validateEdits(profile, const ProfileEdits()).isEmpty, isTrue);
    });

    test('rejects a blank base branch', () {
      expectInvalid(const ProfileEdits(defaultBaseBranch: '  '), 'blank');
    });

    test('rejects an app that is not in the profile', () {
      expectInvalid(
        const ProfileEdits(apps: [AppEdit(path: 'apps/nope')]),
        'no app at apps/nope',
      );
    });

    test('rejects a flavor that is not in the app', () {
      expectInvalid(
        const ProfileEdits(
          apps: [
            AppEdit(
              path: '.',
              flavors: [FlavorEdit(name: 'nope')],
            ),
          ],
        ),
        'no flavor nope',
      );
    });

    test('rejects a store country that is not two letters', () {
      for (final country in ['usa', 'u', '12', '']) {
        expectInvalid(
          ProfileEdits(
            apps: [AppEdit(path: '.', storeCountry: country)],
          ),
          'two letters',
        );
      }
    });

    test('accepts store ids and empty ones, and rejects the rest', () {
      ProfileEdits ids({Map<String, String>? firebase, String? apple}) =>
          ProfileEdits(
            apps: [
              AppEdit(
                path: '.',
                flavors: [
                  FlavorEdit(
                    name: 'dev',
                    firebaseAppId: firebase,
                    appleAppId: apple,
                  ),
                ],
              ),
            ],
          );

      expect(
        validateEdits(
          profile,
          ids(
            firebase: {'android': '1:123456789012:android:abcdef', 'ios': ''},
            apple: '1234567890',
          ),
        ).apps.single.flavors.single.appleAppId,
        '1234567890',
      );
      validateEdits(profile, ids(apple: ''));
      expectInvalid(ids(firebase: {'web': '1:1:web:a'}), 'android or ios');
      expectInvalid(
        ids(firebase: {'android': '1:1:ios:a'}),
        'not a Firebase app id of android',
      );
      expectInvalid(ids(apple: 'com.app'), 'appleAppId');
    });

    test('rejects paths that are absolute, empty or leave the repository', () {
      for (final path in ['/etc/passwd', '', '../x', 'a/../../x', 'a/..']) {
        expectInvalid(
          ProfileEdits(
            apps: [
              AppEdit(
                path: '.',
                flavors: [
                  FlavorEdit(name: 'dev', versionFiles: [path]),
                ],
              ),
            ],
          ),
          'inside the repository',
        );
        expectInvalid(
          ProfileEdits(
            apps: [
              AppEdit(
                path: '.',
                flavors: [FlavorEdit(name: 'dev', entrypoint: path)],
              ),
            ],
          ),
          'inside the repository',
        );
      }
    });
  });
}

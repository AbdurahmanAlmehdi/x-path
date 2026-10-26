import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';

void main() {
  const flavor = FlavorProfile(
    name: 'dev',
    entrypoint: 'lib/main_dev.dart',
    iosBundleId: 'com.example.dev',
    androidAppId: 'com.example.dev',
    iosTeam: 'TEAM123456',
    iosScheme: 'dev',
    infoPlist: 'ios/Runner/Info.plist',
    shorebird: true,
    shorebirdAppId: 'abc',
    prod: true,
    versionFiles: ['pubspec.yaml'],
    sources: ['gradle'],
    firebaseAppId: {'android': '1:1:android:a'},
    appleAppId: '123',
  );

  group('FlavorProfile', () {
    test('round-trips through JSON', () {
      expect(FlavorProfile.fromJson(flavor.toJson()), flavor);
    });

    test('reads defaults for missing optional keys', () {
      final read = FlavorProfile.fromJson(const {
        'name': 'x',
        'entrypoint': 'lib/main.dart',
      });

      expect(read.implicit, isFalse);
      expect(read.prod, isFalse);
      expect(read.shorebird, isFalse);
      expect(read.versionFiles, isEmpty);
      expect(read.toJson().keys, [
        'name',
        'implicit',
        'entrypoint',
        'shorebird',
        'prod',
        'versionFiles',
        'sources',
      ]);
    });

    test('copyWith changes only what is given', () {
      expect(flavor.copyWith(), flavor);

      final changed = flavor.copyWith(
        entrypoint: 'lib/main.dart',
        iosBundleId: 'com.example.ios',
        androidAppId: 'com.example.android',
        shorebird: false,
        prod: false,
        versionFiles: ['pubspec.yaml', 'ios/Runner/Info.plist'],
      );

      expect(changed.entrypoint, 'lib/main.dart');
      expect(changed.iosBundleId, 'com.example.ios');
      expect(changed.androidAppId, 'com.example.android');
      expect(changed.shorebird, isFalse);
      expect(changed.prod, isFalse);
      expect(changed.versionFiles, hasLength(2));
      expect(changed.name, 'dev');
      expect(changed.iosTeam, 'TEAM123456');
      expect(changed.sources, ['gradle']);
      expect(changed.firebaseAppId, {'android': '1:1:android:a'});
      expect(changed.appleAppId, '123');
    });

    test('copyWith sets or clears the store ids', () {
      final changed = flavor.copyWith(
        firebaseAppId: () => {'ios': '1:1:ios:b'},
        appleAppId: () => null,
      );

      expect(changed.firebaseAppId, {'ios': '1:1:ios:b'});
      expect(changed.appleAppId, isNull);
      expect(changed.toJson().containsKey('appleAppId'), isFalse);
    });
  });

  group('AppProfile', () {
    const app = AppProfile(
      name: 'my_app',
      path: 'apps/my_app',
      version: '1.2.3+4',
      storeCountry: 'ly',
      flutterVersion: '3.47.4',
      flutterVersionSource: '.fvmrc',
      hasIos: true,
      hasAndroid: true,
      iosPackageManager: IosPackageManager.cocoapods,
      iosAppExtensions: ['Widgets'],
      iosLinuxLimits: ['the app builds its iOS plugins with CocoaPods'],
      flavors: [flavor],
      plists: [
        PlistVersion(
          path: 'ios/Runner/Info.plist',
          shortVersion: '1.2.3',
          buildNumber: '4',
          literal: true,
        ),
      ],
      keystore: KeystoreProfile(
        propertiesPath: 'android/key.properties',
        propertiesPresent: true,
        storeFile: 'app.jks',
      ),
      shorebird: ShorebirdProfile(appId: 'abc', flavorAppIds: {'dev': 'abc'}),
    );

    test('round-trips through JSON', () {
      expect(AppProfile.fromJson(app.toJson()), app);
    });

    test('reads defaults for missing optional keys', () {
      final read = AppProfile.fromJson(const {'name': 'a', 'path': '.'});

      expect(read.framework, 'flutter');
      expect(read.storeCountry, 'us');
      expect(read.iosPackageManager, IosPackageManager.none);
      expect(read.iosAppExtensions, isEmpty);
      expect(read.iosLinuxLimits, isEmpty);
      expect(read.flavors, isEmpty);
      expect(read.hasIos, isFalse);
    });

    test('copyWith changes only what is given', () {
      expect(app.copyWith(), app);

      final changed = app.copyWith(storeCountry: 'us', flavors: const []);

      expect(changed.storeCountry, 'us');
      expect(changed.flavors, isEmpty);
      expect(changed.name, 'my_app');
      expect(changed.keystore, app.keystore);
      expect(changed.iosAppExtensions, ['Widgets']);
      expect(changed.iosLinuxLimits, app.iosLinuxLimits);
    });

    test('names the package managers', () {
      expect(IosPackageManager.values.map((m) => m.name), [
        'cocoapods',
        'spm',
        'both',
        'none',
      ]);
    });
  });

  group('BranchLayout', () {
    test('knows whether there are release branches', () {
      expect(const BranchLayout().hasReleaseBranches, isFalse);
      expect(
        const BranchLayout(releaseBranches: ['release/1.0']).hasReleaseBranches,
        isTrue,
      );
    });

    test('withDefaultBranch replaces the default branch only', () {
      const layout = BranchLayout(
        defaultBranch: 'main',
        releaseBranches: ['release/1.0'],
      );

      expect(
        layout.withDefaultBranch('dev'),
        const BranchLayout(
          defaultBranch: 'dev',
          releaseBranches: ['release/1.0'],
        ),
      );
    });

    test('round-trips through JSON', () {
      const layout = BranchLayout(
        defaultBranch: 'main',
        releaseBranches: ['release/1.0'],
      );

      expect(BranchLayout.fromJson(layout.toJson()), layout);
    });
  });

  group('ProjectProfile', () {
    const profile = ProjectProfile(
      layout: ProjectLayout.melos,
      apps: [AppProfile(name: 'a', path: 'apps/a')],
      branches: BranchLayout(defaultBranch: 'main'),
      workflows: [
        RepoWorkflow(
          path: '.github/workflows/ci.yml',
          provider: 'github_actions',
          names: ['CI'],
        ),
      ],
    );

    test('round-trips through JSON', () {
      expect(ProjectProfile.fromJson(profile.toJson()), profile);
    });

    test('reads an empty object as an empty single-app profile', () {
      expect(ProjectProfile.fromJson(const {}), const ProjectProfile());
    });

    test('copyWith replaces apps and branches', () {
      expect(profile.copyWith(), profile);

      final changed = profile.copyWith(
        apps: const [],
        branches: const BranchLayout(defaultBranch: 'dev'),
      );

      expect(changed.apps, isEmpty);
      expect(changed.branches.defaultBranch, 'dev');
      expect(changed.layout, ProjectLayout.melos);
      expect(changed.workflows, profile.workflows);
    });

    test('names the layouts', () {
      expect(ProjectLayout.values.map((l) => l.name), ['single', 'melos']);
    });
  });

  test('RepoWorkflow reads no names as none', () {
    expect(
      RepoWorkflow.fromJson(const {'path': 'p', 'provider': 'codemagic'}).names,
      isEmpty,
    );
  });

  test('ShorebirdProfile reads no flavors as none', () {
    expect(
      ShorebirdProfile.fromJson(const {'appId': 'a'}).flavorAppIds,
      isEmpty,
    );
  });
}

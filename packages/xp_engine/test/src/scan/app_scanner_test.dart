import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/repo_builder.dart';

/// Scans a plain app with [overrides] and returns the result.
Future<ScanResult> scanApp1(Map<String, String?> overrides) =>
    scanFiles(app(overrides: overrides));

AppProfile only(ScanResult result) => result.profile.apps.single;

Finding finding(ScanResult result, String code) =>
    result.findings.singleWhere((finding) => finding.code == code);

List<String> codes(ScanResult result) => [
  for (final finding in result.findings) finding.code,
];

/// Gradle with `dev` and `prod` flavors.
String flavoredGradle({String dev = 'com.example.dev'}) => gradle(
  flavors:
      '''
productFlavors {
    dev { applicationId "$dev" }
    prod { applicationId "com.example" }
}''',
);

/// Xcode configurations for `dev` and `prod`.
Map<String, Map<String, String>> flavoredRunner({
  String dev = 'com.example.dev',
  String prod = 'com.example',
  String? team = 'TEAM000001',
}) => {
  ...configurations('dev', iosSettings(bundleId: dev, team: team)),
  ...configurations('prod', iosSettings(bundleId: prod, team: team)),
};

Map<String, String?> flavored({
  String? gradleText,
  Map<String, Map<String, String>>? runner,
  Map<String, String?> more = const {},
}) => {
  'android/app/build.gradle': gradleText ?? flavoredGradle(),
  'ios/Runner.xcodeproj/project.pbxproj': pbxproj(
    runner: runner ?? flavoredRunner(),
  ),
  'ios/Runner.xcodeproj/xcshareddata/xcschemes/dev.xcscheme': scheme(
    'Release-dev',
  ),
  'ios/Runner.xcodeproj/xcshareddata/xcschemes/prod.xcscheme': scheme(
    'Release-prod',
  ),
  'ios/Runner.xcodeproj/xcshareddata/xcschemes/Runner.xcscheme': scheme(
    'Release',
  ),
  'lib/main_dev.dart': '',
  'lib/main_prod.dart': '',
  ...more,
};

void main() {
  group('a plain app', () {
    test('has one implicit flavor that stands for the whole app', () async {
      final result = await scanApp1({});

      final flavor = only(result).flavors.single;
      expect(flavor.name, 'default');
      expect(flavor.implicit, isTrue);
      expect(flavor.prod, isTrue);
      expect(flavor.entrypoint, 'lib/main.dart');
      expect(flavor.androidAppId, 'com.example.demo');
      expect(flavor.iosBundleId, 'com.example.demo');
      expect(flavor.iosTeam, 'TEAM000001');
      expect(flavor.sources, isEmpty);
      expect(flavor.versionFiles, ['pubspec.yaml']);
      expect(only(result).version, '1.0.0+1');
      expect(only(result).flutterVersion, '3.47.4');
      expect(only(result).flutterVersionSource, '.fvmrc');
      expect(result.findings, isEmpty);
    });

    test('has the paths of an app below the root', () async {
      final result = await scanFiles({
        'pubspec.yaml': 'name: ws\nworkspace:\n  - apps/a\n',
        '.fvmrc': '{"flutter": "3.0.0"}',
        ...app(dir: 'apps/a', overrides: {'.fvmrc': null}),
      });

      final profile = only(result);
      expect(profile.path, 'apps/a');
      expect(profile.flavors.single.versionFiles, ['apps/a/pubspec.yaml']);
      expect(profile.keystore!.propertiesPath, 'apps/a/android/key.properties');
      expect(profile.flutterVersionSource, '.fvmrc');
    });

    test('only has the platforms it has', () async {
      final androidOnly = await scanApp1({
        'ios/Runner.xcodeproj/project.pbxproj': null,
        'ios/Runner/Info.plist': null,
        'ios/Podfile': null,
      });
      final iosOnly = await scanApp1({
        'android/app/build.gradle': null,
        'android/key.properties': null,
      });

      expect(only(androidOnly).hasIos, isFalse);
      expect(only(androidOnly).hasAndroid, isTrue);
      expect(only(androidOnly).flavors.single.iosBundleId, isNull);
      expect(only(androidOnly).iosPackageManager, IosPackageManager.none);
      expect(androidOnly.findings, isEmpty);
      expect(only(iosOnly).hasAndroid, isFalse);
      expect(only(iosOnly).keystore, isNull);
      expect(only(iosOnly).flavors.single.androidAppId, isNull);
      expect(iosOnly.findings, isEmpty);
    });

    test('is an error when the pubspec has no usable version', () async {
      for (final version in [null, 'one', '1.0']) {
        final result = await scanApp1({
          'pubspec.yaml': pubspec(version: version),
        });

        final problem = finding(result, 'pubspec_version_missing');
        expect(problem.severity, FindingSeverity.error);
        expect(problem.path, 'pubspec.yaml');
      }
    });

    test('is an error when the pubspec version is not a string', () async {
      final result = await scanApp1({
        'pubspec.yaml': pubspec(version: null)
            .replaceFirst('dependencies', 'version: 1\ndependencies'),
      });

      expect(only(result).version, isNull);
      expect(
        finding(result, 'pubspec_version_missing').message,
        contains('"1"'),
      );
    });

    test('accepts a version without a build number', () async {
      final result = await scanApp1({
        'pubspec.yaml': pubspec(version: '2.1.0'),
      });

      expect(result.findings, isEmpty);
    });
  });

  group('flavors', () {
    test('are joined from Gradle, Xcode and entrypoints', () async {
      final result = await scanApp1(flavored());

      expect(only(result).flavors.map((f) => f.name), ['dev', 'prod']);
      final dev = only(result).flavors.first;
      expect(dev.implicit, isFalse);
      expect(dev.androidAppId, 'com.example.dev');
      expect(dev.iosBundleId, 'com.example.dev');
      expect(dev.iosScheme, 'dev');
      expect(dev.entrypoint, 'lib/main_dev.dart');
      expect(dev.prod, isFalse);
      expect(dev.sources, ['gradle', 'xcscheme', 'entrypoint']);
      expect(only(result).flavors.last.prod, isTrue);
      expect(result.findings, isEmpty);
    });

    test('count production by name', () async {
      for (final name in ['production', 'release', 'live']) {
        final result = await scanApp1({
          ...flavored(),
          'android/app/build.gradle': gradle(
            flavors: 'productFlavors { $name { applicationId "x" } }',
          ),
        });

        expect(
          only(result).flavors.firstWhere((f) => f.name == name).prod,
          isTrue,
          reason: name,
        );
      }
    });

    test('suggest marking one when none looks like production', () async {
      final result = await scanApp1({
        'android/app/build.gradle': gradle(
          flavors: 'productFlavors { alpha { applicationId "x" } }',
        ),
      });

      expect(finding(result, 'no_prod_flavor').severity, FindingSeverity.info);
    });

    test('come from flutter_flavorizr alone as a fallback for ids', () async {
      final result = await scanApp1({
        'flavorizr.yaml': '''
flavors:
  qa:
    android:
      applicationId: com.example.qa
    ios:
      bundleId: com.example.qa.ios
  bare: {}
  broken: text
''',
      });

      final qa = only(result).flavors.firstWhere((f) => f.name == 'qa');
      expect(qa.androidAppId, 'com.example.qa');
      expect(qa.iosBundleId, 'com.example.qa.ios');
      expect(qa.sources, ['flavorizr']);
      expect(only(result).flavors.map((f) => f.name), ['qa', 'bare', 'broken']);
      expect(
        result.findings
            .where((f) => f.code == 'android_flavor_missing')
            .map((f) => f.flavor),
        ['qa', 'bare', 'broken'],
      );
      expect(
        result.findings
            .where((f) => f.code == 'ios_flavor_without_scheme')
            .map((f) => f.flavor),
        ['qa', 'bare', 'broken'],
      );
      expect(
        finding(result, 'bundle_id_platform_mismatch').message,
        contains('com.example.qa'),
      );
    });

    test('warn about a flavorizr.yaml that is not YAML', () async {
      final result = await scanApp1({'flavorizr.yaml': 'a: [b'});

      expect(finding(result, 'flavorizr_yaml_invalid').path, 'flavorizr.yaml');
      expect(only(result).flavors.single.implicit, isTrue);
    });

    test('come from the entrypoints when no build system has any', () async {
      final result = await scanApp1({
        'lib/main_alpha.dart': '',
        'lib/main_beta.dart': '',
      });

      expect(only(result).flavors.map((f) => f.name), ['alpha', 'beta']);
      expect(only(result).flavors.first.sources, ['entrypoint']);
      expect(only(result).flavors.first.implicit, isFalse);
    });

    test('do not become flavors from stray entrypoints', () async {
      final result = await scanApp1({
        ...flavored(),
        'lib/main_preview.dart': '',
      });

      expect(only(result).flavors.map((f) => f.name), ['dev', 'prod']);
      final stray = finding(result, 'entrypoint_without_flavor');
      expect(stray.severity, FindingSeverity.info);
      expect(stray.path, 'lib/main_preview.dart');
    });

    test(
      'fall back to main.dart when other flavors have an entrypoint',
      () async {
        final result = await scanApp1({
          ...flavored(),
          'lib/main_prod.dart': null,
        });

        expect(only(result).flavors.last.entrypoint, 'lib/main.dart');
        expect(finding(result, 'entrypoint_missing').flavor, 'prod');
      },
    );

    test('use main.dart quietly when no flavor has an entrypoint', () async {
      final result = await scanApp1({
        ...flavored(),
        'lib/main_dev.dart': null,
        'lib/main_prod.dart': null,
      });

      expect(only(result).flavors.map((f) => f.entrypoint), [
        'lib/main.dart',
        'lib/main.dart',
      ]);
      expect(codes(result), isNot(contains('entrypoint_missing')));
    });

    test('warn when Gradle has flavors it cannot read', () async {
      final result = await scanApp1({
        'android/app/build.gradle': gradle(
          flavors: 'productFlavors { flavorsFromFile() }',
        ),
      });

      expect(
        finding(result, 'gradle_flavors_unreadable').severity,
        FindingSeverity.warning,
      );
    });

    test('warn about several Gradle dimensions', () async {
      final result = await scanApp1({
        'android/app/build.gradle': gradle(
          flavors: '''
productFlavors {
  a { dimension "x" }
  b { dimension "y" }
}''',
        ),
      });

      expect(
        finding(result, 'gradle_multiple_dimensions').message,
        contains('x, y'),
      );
    });

    test('use the application id suffix of Gradle', () async {
      final result = await scanApp1({
        'android/app/build.gradle': gradle(
          flavors: 'productFlavors { dev { applicationIdSuffix ".dev" } }',
        ),
      });

      expect(only(result).flavors.single.androidAppId, 'com.example.demo.dev');
    });

    test(
      'read Gradle scripts besides build.gradle, build script first',
      () async {
        final result = await scanApp1({
          'android/app/a_flavors.gradle':
              'productFlavors { dev { applicationId "com.other" } }',
          'android/app/build.gradle.kts':
              'productFlavors { dev { applicationId = "com.first" } }',
          'android/app/notes.txt': 'productFlavors { ghost { } }',
        });

        expect(only(result).flavors.map((f) => f.name), ['dev']);
        expect(only(result).flavors.single.androidAppId, 'com.first');
      },
    );
  });

  group('bundle and application ids', () {
    test('differing between platforms are a warning', () async {
      final result = await scanApp1(
        flavored(runner: flavoredRunner(prod: 'com.other.app')),
      );

      final mismatch = finding(result, 'bundle_id_platform_mismatch');
      expect(mismatch.severity, FindingSeverity.warning);
      expect(mismatch.flavor, 'prod');
      expect(mismatch.message, isNot(contains('typo')));
    });

    test('differing by a character or two look like a typo', () async {
      final result = await scanApp1(
        flavored(runner: flavoredRunner(dev: 'com.exxample.dev')),
      );

      final mismatch = finding(result, 'bundle_id_platform_mismatch');
      expect(mismatch.message, contains('looks like a typo'));
      expect(mismatch.fix, contains('misspelled'));
    });

    test('that disagree with flutter_flavorizr are an error', () async {
      final result = await scanApp1({
        ...flavored(),
        'flavorizr.yaml': '''
flavors:
  dev:
    android:
      applicationId: com.declared.android
    ios:
      bundleId: com.declared.ios
  prod:
    android:
      applicationId: com.example
    ios:
      bundleId: com.example
''',
      });

      final drift = result.findings
          .where((f) => f.code == 'bundle_id_config_drift')
          .toList();
      expect(drift, hasLength(2));
      expect(drift.every((f) => f.severity == FindingSeverity.error), isTrue);
      expect(drift.map((f) => f.flavor), ['dev', 'dev']);
      expect(drift.first.message, contains('com.declared.android'));
      expect(drift.last.message, contains('com.declared.ios'));
    });

    test(
      'that differ between the configurations of a flavor are a warning',
      () async {
        final result = await scanApp1(
          flavored(
            runner: {
              ...flavoredRunner(),
              'Debug-dev': iosSettings(
                bundleId: 'com.example.dev.debug',
                team: 'TEAM000001',
              ),
            },
          ),
        );

        expect(
          finding(result, 'bundle_id_configs_differ').severity,
          FindingSeverity.warning,
        );
      },
    );

    test('that are build variables are unresolved', () async {
      final result = await scanApp1(
        flavored(runner: flavoredRunner(dev: r'$(DEV_BUNDLE_ID)')),
      );

      expect(only(result).flavors.first.iosBundleId, isNull);
      expect(finding(result, 'ios_bundle_id_unresolved').flavor, 'dev');
    });

    test('are unknown for a flavor that has no Xcode configuration', () async {
      final result = await scanApp1({
        ...flavored(),
        'ios/Runner.xcodeproj/project.pbxproj': pbxproj(
          runner: configurations(
            'prod',
            iosSettings(bundleId: 'com.example', team: 'T'),
          ),
        ),
      });

      expect(only(result).flavors.first.iosBundleId, isNull);
      expect(finding(result, 'ios_flavor_without_scheme').flavor, 'dev');
    });
  });

  group('signing teams', () {
    test('missing or variable are a warning', () async {
      for (final team in [null, r'$(TEAM)']) {
        final result = await scanApp1({
          'ios/Runner.xcodeproj/project.pbxproj': pbxproj(
            runner: configurations(
              null,
              iosSettings(bundleId: 'com.example.demo', team: team),
            ),
          ),
        });

        expect(
          finding(result, 'ios_team_missing').severity,
          FindingSeverity.warning,
        );
        expect(only(result).flavors.single.iosTeam, isNull);
      }
    });

    test('come from the project when the target sets none', () async {
      final result = await scanApp1({
        'ios/Runner.xcodeproj/project.pbxproj': pbxproj(
          runner: configurations(
            null,
            iosSettings(bundleId: 'com.example.demo'),
          ),
          project: {
            'Release': {'DEVELOPMENT_TEAM': 'TEAMPROJECT'},
          },
        ),
      });

      expect(only(result).flavors.single.iosTeam, 'TEAMPROJECT');
    });
  });

  group('the Xcode project', () {
    test('that cannot be read is a warning', () async {
      for (final text in ['garbage', null]) {
        final result = await scanApp1({
          'ios/Runner.xcodeproj/project.pbxproj': text,
          'ios/Runner.xcodeproj/xcshareddata/xcschemes/x.xcscheme': scheme(
            'Release-x',
          ),
        });

        expect(
          finding(result, 'xcode_project_unreadable').severity,
          FindingSeverity.warning,
        );
        expect(codes(result), isNot(contains('ios_flavor_without_scheme')));
        expect(only(result).hasIos, isTrue);
      }
    });

    test(
      'names its scheme as the flavor when only Xcode has the flavor',
      () async {
        final result = await scanApp1({
          'ios/Runner.xcodeproj/xcshareddata/xcschemes/x.xcscheme': scheme(
            'Release-x',
          ),
          'ios/Runner.xcodeproj/xcshareddata/xcschemes/notes.txt': 'Release-y',
          'ios/Runner.xcodeproj/xcshareddata/xcschemes/dir.xcscheme/inner': '',
          'ios/Runner.xcodeproj/xcshareddata/xcschemes/empty.xcscheme':
              '<Scheme/>',
        });

        expect(only(result).flavors.map((f) => f.name), ['x']);
        expect(finding(result, 'android_flavor_missing').flavor, 'x');
      },
    );

    test('integrates plugins with CocoaPods, SPM or both', () async {
      final spm = pbxproj(
        runner: configurations(
          null,
          iosSettings(bundleId: 'com.example.demo', team: 'T'),
        ),
        spm: true,
      );

      final pods = await scanApp1({});
      final swiftPackages = await scanApp1({
        'ios/Podfile': null,
        'ios/Runner.xcodeproj/project.pbxproj': spm,
      });
      final both = await scanApp1({
        'ios/Runner.xcodeproj/project.pbxproj': spm,
      });
      final neither = await scanApp1({'ios/Podfile': null});

      expect(only(pods).iosPackageManager, IosPackageManager.cocoapods);
      expect(only(swiftPackages).iosPackageManager, IosPackageManager.spm);
      expect(only(both).iosPackageManager, IosPackageManager.both);
      expect(
        finding(both, 'ios_spm_and_cocoapods').severity,
        FindingSeverity.info,
      );
      expect(only(neither).iosPackageManager, IosPackageManager.none);
    });
  });

  group('Info.plist versions', () {
    test('as build variables are fine', () async {
      final result = await scanApp1({});

      expect(only(result).plists.single.literal, isFalse);
      expect(only(result).plists.single.shortVersion, r'$(FLUTTER_BUILD_NAME)');
      expect(only(result).flavors.single.infoPlist, 'ios/Runner/Info.plist');
    });

    test('that are literal are a warning and a version file', () async {
      final result = await scanApp1({
        'ios/Runner/Info.plist': plist(shortVersion: '1.0.0', build: '1'),
      });

      expect(only(result).plists.single.literal, isTrue);
      expect(only(result).flavors.single.versionFiles, [
        'pubspec.yaml',
        'ios/Runner/Info.plist',
      ]);
      final literal = finding(result, 'plist_literal_version');
      expect(literal.severity, FindingSeverity.warning);
      expect(literal.path, 'ios/Runner/Info.plist');
      expect(codes(result), isNot(contains('version_files_out_of_sync')));
    });

    test('that disagree with the pubspec are an error', () async {
      for (final plistText in [
        plist(shortVersion: '1.0.1', build: '1'),
        plist(shortVersion: '1.0.0', build: '2'),
        plist(shortVersion: r'$(FLUTTER_BUILD_NAME)', build: '2'),
        plist(shortVersion: '1.0.1'),
        plist(build: '2'),
      ]) {
        final result = await scanApp1({'ios/Runner/Info.plist': plistText});

        final problem = finding(result, 'version_files_out_of_sync');
        expect(problem.severity, FindingSeverity.error, reason: plistText);
        expect(problem.path, 'ios/Runner/Info.plist');
      }
    });

    test('that agree with the pubspec raise no error', () async {
      for (final plistText in [
        plist(shortVersion: '1.0.0'),
        plist(build: '1'),
        plist(shortVersion: '1.0.0', build: r'$(FLUTTER_BUILD_NUMBER)'),
      ]) {
        final result = await scanApp1({'ios/Runner/Info.plist': plistText});

        expect(codes(result), isNot(contains('version_files_out_of_sync')));
      }
    });

    test('are not compared when the pubspec has no version', () async {
      final result = await scanApp1({
        'pubspec.yaml': pubspec(version: null),
        'ios/Runner/Info.plist': plist(shortVersion: '9.9.9', build: '9'),
      });

      expect(codes(result), isNot(contains('version_files_out_of_sync')));
    });

    test('are read once per plist, whatever the flavors', () async {
      final result = await scanApp1({
        ...flavored(),
        'ios/Runner/Info.plist': plist(shortVersion: '1.0.0', build: '1'),
      });

      expect(only(result).plists, hasLength(1));
      expect(
        result.findings.where((f) => f.code == 'plist_literal_version'),
        hasLength(1),
      );
      expect(only(result).flavors.map((f) => f.versionFiles), [
        ['pubspec.yaml', 'ios/Runner/Info.plist'],
        ['pubspec.yaml', 'ios/Runner/Info.plist'],
      ]);
    });

    test('belong to the plist a flavor names, with SRCROOT stripped', () async {
      final result = await scanApp1({
        'ios/Runner.xcodeproj/project.pbxproj': pbxproj(
          runner: configurations(
            null,
            iosSettings(
              bundleId: 'com.example.demo',
              team: 'T',
              plist: r'$(SRCROOT)/Runner/Other.plist',
            ),
          ),
        ),
        'ios/Runner/Other.plist': plist(shortVersion: '1.0.0', build: '1'),
      });

      expect(only(result).flavors.single.infoPlist, 'ios/Runner/Other.plist');
    });

    test('that are missing are a warning', () async {
      final result = await scanApp1({'ios/Runner/Info.plist': null});

      expect(only(result).flavors.single.infoPlist, isNull);
      expect(finding(result, 'plist_missing').path, 'ios/Runner/Info.plist');
      expect(only(result).plists, isEmpty);
    });

    test('are skipped when the target names none', () async {
      final result = await scanApp1({
        'ios/Runner.xcodeproj/project.pbxproj': pbxproj(
          runner: configurations(
            null,
            iosSettings(bundleId: 'com.example.demo', team: 'T', plist: null),
          ),
        ),
      });

      expect(only(result).flavors.single.infoPlist, isNull);
      expect(only(result).plists, isEmpty);
    });
  });

  group('Shorebird', () {
    test('ids by flavor mark the flavors that can be patched', () async {
      final result = await scanApp1({
        ...flavored(),
        'shorebird.yaml': '''
app_id: id-dev
flavors:
  dev: id-dev
  prod: id-prod
''',
      });

      expect(
        only(result).shorebird,
        const ShorebirdProfile(
          appId: 'id-dev',
          flavorAppIds: {'dev': 'id-dev', 'prod': 'id-prod'},
        ),
      );
      expect(only(result).flavors.map((f) => f.shorebirdAppId), [
        'id-dev',
        'id-prod',
      ]);
      expect(only(result).flavors.every((f) => f.shorebird), isTrue);
      expect(result.findings, isEmpty);
    });

    test('app id of a plain app belongs to its only build', () async {
      final result = await scanApp1({'shorebird.yaml': 'app_id: the-id\n'});

      expect(only(result).flavors.single.shorebird, isTrue);
      expect(only(result).flavors.single.shorebirdAppId, 'the-id');
      expect(result.findings, isEmpty);
    });

    test('app id without flavors is a warning for a flavored app', () async {
      final result = await scanApp1({
        ...flavored(),
        'shorebird.yaml': 'app_id: the-id\n',
      });

      expect(only(result).flavors.any((f) => f.shorebird), isFalse);
      expect(
        finding(result, 'shorebird_no_flavor_ids').severity,
        FindingSeverity.warning,
      );
    });

    test(
      'flavors the file does not list or the app lacks are reported',
      () async {
        final result = await scanApp1({
          ...flavored(),
          'shorebird.yaml': '''
flavors:
  dev: id-dev
  ghost: id-ghost
  nothing:
''',
        });

        expect(only(result).shorebird!.appId, isNull);
        expect(only(result).flavors.map((f) => f.shorebird), [true, false]);
        expect(finding(result, 'shorebird_flavor_without_id').flavor, 'prod');
        expect(
          finding(result, 'shorebird_flavor_without_id').severity,
          FindingSeverity.info,
        );
        final unknown = result.findings.where(
          (f) => f.code == 'shorebird_unknown_flavor',
        );
        expect(unknown.map((f) => f.flavor), ['ghost']);
      },
    );

    test('that is not YAML or has no ids is an error', () async {
      for (final text in ['a: [b', '', 'other: 1', 'flavors: {}']) {
        final result = await scanApp1({'shorebird.yaml': text});

        expect(only(result).shorebird, isNull, reason: text);
        final problem = finding(result, 'shorebird_yaml_invalid');
        expect(problem.severity, FindingSeverity.error, reason: text);
      }
    });

    test('is absent for an app that does not use it', () async {
      expect(only(await scanApp1({})).shorebird, isNull);
    });
  });

  group('the Android keystore', () {
    test('is read from key.properties when it is there', () async {
      final result = await scanApp1({});

      expect(
        only(result).keystore,
        const KeystoreProfile(
          propertiesPath: 'android/key.properties',
          propertiesPresent: true,
          storeFile: 'release.jks',
        ),
      );
      expect(result.findings, isEmpty);
    });

    test('has no store file when key.properties does not name one', () async {
      final result = await scanApp1({'android/key.properties': 'keyAlias=a\n'});

      expect(only(result).keystore!.propertiesPresent, isTrue);
      expect(only(result).keystore!.storeFile, isNull);
    });

    test('never reads the passwords', () async {
      final result = await scanApp1({
        'android/key.properties':
            'storePassword=hunter2\nkeyPassword=hunter2\nstoreFile = a.jks\n',
      });

      expect(
        only(result).keystore!.toJson().toString(),
        isNot(contains('hunter2')),
      );
      expect(only(result).keystore!.storeFile, 'a.jks');
    });

    test('is a warning when referenced but absent', () async {
      final result = await scanApp1({'android/key.properties': null});

      expect(only(result).keystore!.propertiesPresent, isFalse);
      final missing = finding(result, 'keystore_properties_missing');
      expect(missing.severity, FindingSeverity.warning);
      expect(missing.path, 'android/key.properties');
    });

    test('is resolved against the android directory', () async {
      final result = await scanApp1({
        'android/app/build.gradle': gradle().replaceFirst(
          '"key.properties"',
          '"secrets/key.properties"',
        ),
        'android/secrets/key.properties': 'storeFile=x.jks',
      });

      expect(
        only(result).keystore!.propertiesPath,
        'android/secrets/key.properties',
      );
      expect(only(result).keystore!.propertiesPresent, isTrue);
    });

    test('is an info when Gradle does not reference one', () async {
      final result = await scanApp1({
        'android/app/build.gradle': gradle(keystore: false),
      });

      expect(only(result).keystore, isNull);
      expect(
        finding(result, 'keystore_not_referenced').severity,
        FindingSeverity.info,
      );
    });
  });

  group('the Flutter version', () {
    test('is missing without any .fvmrc', () async {
      final result = await scanApp1({'.fvmrc': null});

      expect(only(result).flutterVersion, isNull);
      expect(only(result).flutterVersionSource, isNull);
      final missing = finding(result, 'fvmrc_missing');
      expect(missing.severity, FindingSeverity.warning);
      expect(missing.app, '.');
    });

    test('is the pin of the app, not of the repository', () async {
      final result = await scanFiles({
        'pubspec.yaml': 'name: ws\nworkspace:\n  - apps/a\n  - apps/b\n',
        '.fvmrc': '{"flutter": "3.0.0"}',
        ...app(dir: 'apps/a', overrides: {'.fvmrc': '{"flutter": "3.1.0"}'}),
        ...app(dir: 'apps/b', overrides: {'.fvmrc': null}),
      });

      expect(result.profile.apps.map((a) => a.flutterVersion), [
        '3.1.0',
        '3.0.0',
      ]);
      expect(result.profile.apps.map((a) => a.flutterVersionSource), [
        'apps/a/.fvmrc',
        '.fvmrc',
      ]);
    });

    test('is not missing when the file is invalid, only invalid', () async {
      final result = await scanApp1({'.fvmrc': 'nope'});

      expect(only(result).flutterVersion, isNull);
      expect(only(result).flutterVersionSource, '.fvmrc');
      expect(codes(result), ['fvmrc_invalid']);
    });
  });

  group('the app itself', () {
    test('needs a Flutter dependency, a name and a platform', () async {
      for (final override in [
        {'pubspec.yaml': 'name: x\ndependencies:\n  http: any\n'},
        {'pubspec.yaml': 'dependencies:\n  flutter:\n    sdk: flutter\n'},
        {'pubspec.yaml': null},
      ]) {
        final result = await scanApp1(override);

        expect(result.profile.apps, isEmpty, reason: '$override');
        expect(codes(result), contains('no_flutter_app'));
      }
    });
  });
}

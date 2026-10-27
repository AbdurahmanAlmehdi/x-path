// Equal constants are identical and never compare props, so these tests
// build their values at run time.
// ignore_for_file: prefer_const_constructors
// ignore_for_file: prefer_const_literals_to_create_immutables

import 'package:test/test.dart';
import 'package:xp_engine/src/scan/xcode_project_parser.dart';

/// A pbxproj with a `Runner` app, a test bundle and an extension.
const _pbxproj = r'''
// !$*UTF8*$!
{
	archiveVersion = 1;
	objects = {

/* Begin PBXNativeTarget section */
		AA01 /* Runner */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = CL01 /* Build configuration list for PBXNativeTarget "Runner" */;
			buildPhases = (
			);
			name = Runner;
			productType = "com.apple.product-type.application";
		};
		AA02 /* RunnerTests */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = CL02;
			name = RunnerTests;
			productType = "com.apple.product-type.bundle.unit-test";
		};
		AA03 /* Extension */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = CL02;
			name = Extension;
			productType = "com.apple.product-type.app-extension";
		};
/* End PBXNativeTarget section */

		AA00 /* Project object */ = {
			isa = PBXProject;
			buildConfigurationList = CL00;
			targets = (
				AA01 /* Runner */,
				AA02 /* RunnerTests */,
				AA03 /* Extension */,
				AA04
			);
		};
		AA04 = {
			isa = PBXAggregateTarget;
			name = Aggregate;
		};
		CL00 = {
			isa = XCConfigurationList;
			buildConfigurations = (
				CF00,
			);
		};
		CL01 = {
			isa = XCConfigurationList;
			buildConfigurations = (
				CF01,
				CF02,
			);
		};
		CL02 = {
			isa = XCConfigurationList;
			buildConfigurations = (
			);
		};
		CF00 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				DEVELOPMENT_TEAM = TEAMPROJ01;
				IPHONEOS_DEPLOYMENT_TARGET = 15.0;
			};
			name = Release;
		};
		CF01 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				PRODUCT_BUNDLE_IDENTIFIER = com.example.app;
				PRODUCT_NAME = "$(TARGET_NAME)";
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				QUOTED = "tab\there \"quoted\" \\ back\nline";
			};
			name = Release;
		};
		CF02 /* Release-dev */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				PRODUCT_BUNDLE_IDENTIFIER = com.example.dev;
			};
			name = "Release-dev";
		};
	};
	rootObject = AA00 /* Project object */;
}
''';

/// How Flutter's own Run Script phases call its build script.
const _backend =
    r'/bin/sh "$FLUTTER_ROOT/packages/flutter_tools/bin/xcode_backend.sh"';

/// A pbxproj with build phases, groups and `.xcconfig` files.
const _phases = r'''
{
	objects = {
		T1 = {
			isa = PBXNativeTarget;
			buildConfigurationList = L1;
			buildPhases = ( P1, P2, P3, P4, P5 );
			name = Runner;
			productType = "com.apple.product-type.application";
		};
		P1 = {
			isa = PBXShellScriptBuildPhase;
			name = "Run Script";
			shellScript = "/bin/sh \"$FLUTTER_ROOT/packages/flutter_tools/bin/xcode_backend.sh\" build\n";
		};
		P2 = {
			isa = PBXShellScriptBuildPhase;
			shellScript = "cp a b\n";
		};
		P3 = {
			isa = PBXShellScriptBuildPhase;
			name = "[CP] Embed Pods Frameworks";
			shellScript = ( );
		};
		P4 = {
			isa = PBXResourcesBuildPhase;
			files = ( B1, B2, B3, B4, B5, B6, B7 );
		};
		P5 = { isa = PBXSourcesBuildPhase; files = ( B8 ); };
		B1 = { isa = PBXBuildFile; fileRef = F1; };
		B2 = { isa = PBXBuildFile; fileRef = V1; };
		B3 = { isa = PBXBuildFile; fileRef = F3; };
		B4 = { isa = PBXBuildFile; fileRef = F4; };
		B5 = { isa = PBXBuildFile; fileRef = F5; };
		B6 = { isa = PBXBuildFile; fileRef = F6; };
		B7 = { isa = PBXBuildFile; fileRef = F7; };
		B8 = { isa = PBXBuildFile; fileRef = F8; };
		G0 = { isa = PBXGroup; children = ( G1, G2, G3 ); sourceTree = "<group>"; };
		G1 = { isa = PBXGroup; children = ( F1, V1, F8 ); path = Runner; sourceTree = "<group>"; };
		G2 = { isa = PBXGroup; children = ( X1 ); name = Flutter; path = Flutter; sourceTree = "<group>"; };
		G3 = { isa = PBXGroup; children = ( F5 ); path = Frameworks; sourceTree = SDKROOT; };
		F1 = { isa = PBXFileReference; path = Assets.xcassets; sourceTree = "<group>"; };
		V1 = { isa = PBXVariantGroup; children = ( F2 ); name = LaunchScreen.storyboard; sourceTree = "<group>"; };
		F2 = { isa = PBXFileReference; name = Base; path = Base.lproj/LaunchScreen.storyboard; sourceTree = "<group>"; };
		F3 = { isa = PBXFileReference; path = Config/GoogleService-Info.plist; sourceTree = SOURCE_ROOT; };
		F4 = { isa = PBXFileReference; path = /tmp/x.plist; sourceTree = "<absolute>"; };
		F5 = { isa = PBXFileReference; path = Thing.bundle; sourceTree = "<group>"; };
		F6 = { isa = PBXFileReference; sourceTree = "<group>"; };
		F7 = { isa = PBXFileReference; path = Loose.json; sourceTree = "<group>"; };
		F8 = { isa = PBXFileReference; path = AppDelegate.swift; sourceTree = "<group>"; };
		X1 = { isa = PBXFileReference; path = devRelease.xcconfig; sourceTree = "<group>"; };
		X2 = { isa = PBXFileReference; path = Project.xcconfig; sourceTree = SOURCE_ROOT; };
		L1 = { isa = XCConfigurationList; buildConfigurations = ( C1, C2, C3 ); };
		C1 = {
			isa = XCBuildConfiguration;
			baseConfigurationReference = X1;
			buildSettings = { SHARED = target; };
			name = "Release-dev";
		};
		C2 = { isa = XCBuildConfiguration; buildSettings = { }; name = "Release-Staging"; };
		C3 = { isa = XCBuildConfiguration; buildSettings = { }; name = "Release-STAGING"; };
		L0 = { isa = XCConfigurationList; buildConfigurations = ( C0 ); };
		C0 = {
			isa = XCBuildConfiguration;
			baseConfigurationReference = X2;
			buildSettings = { SHARED = project; ONLY_PROJECT = project; };
			name = "Release-dev";
		};
		R = {
			isa = PBXProject;
			buildConfigurationList = L0;
			mainGroup = G0;
			targets = ( T1 );
		};
	};
	rootObject = R;
}
''';

void main() {
  group('parseXcodeProject', () {
    final project = parseXcodeProject(_pbxproj)!;

    test('reads native targets with their configurations', () {
      expect(project.targets.map((target) => target.name), [
        'Runner',
        'RunnerTests',
        'Extension',
      ]);
      expect(project.targets.map((target) => target.isApplication), [
        true,
        false,
        false,
      ]);
      expect(project.targets.map((target) => target.isAppExtension), [
        false,
        false,
        true,
      ]);
      expect(project.targets.first.configurations.map((c) => c.name), [
        'Release',
        'Release-dev',
      ]);
    });

    test('keeps string settings, unescaped, and drops lists', () {
      final settings = project.targets.first.configurations.first.settings;

      expect(settings['PRODUCT_BUNDLE_IDENTIFIER'], 'com.example.app');
      expect(settings['PRODUCT_NAME'], r'$(TARGET_NAME)');
      expect(settings['QUOTED'], 'tab\there "quoted" \\ back\nline');
      expect(settings.containsKey('LD_RUNPATH_SEARCH_PATHS'), isFalse);
    });

    test('reads the project configurations', () {
      expect(project.projectConfigurations.single.name, 'Release');
    });

    test('has no Swift packages unless it references them', () {
      expect(project.usesSwiftPackages, isFalse);
    });

    test('finds the Runner app target', () {
      expect(project.appTarget!.name, 'Runner');
    });

    test('falls back to the first application, or to none', () {
      final other = parseXcodeProject(
        _pbxproj.replaceFirst('name = Runner;', 'name = Other;'),
      )!;
      final none = parseXcodeProject(
        _pbxproj.replaceAll(
          '"com.apple.product-type.application"',
          '"com.apple.product-type.tool"',
        ),
      )!;

      expect(other.appTarget!.name, 'Other');
      expect(none.appTarget, isNull);
    });

    test('settingsOf lets the target win over the project', () {
      final target = project.appTarget!;

      expect(project.settingsOf(target, 'Release'), {
        'DEVELOPMENT_TEAM': 'TEAMPROJ01',
        'IPHONEOS_DEPLOYMENT_TARGET': '15.0',
        'PRODUCT_BUNDLE_IDENTIFIER': 'com.example.app',
        'PRODUCT_NAME': r'$(TARGET_NAME)',
        'QUOTED': 'tab\there "quoted" \\ back\nline',
      });
      expect(project.settingsOf(target, 'Release-dev'), {
        'PRODUCT_BUNDLE_IDENTIFIER': 'com.example.dev',
      });
      expect(project.settingsOf(target, 'Release-nope'), isNull);
    });

    test('settingsOf uses the project alone when the target has no such '
        'configuration', () {
      final tests = project.targets[1];

      expect(project.settingsOf(tests, 'Release'), {
        'DEVELOPMENT_TEAM': 'TEAMPROJ01',
        'IPHONEOS_DEPLOYMENT_TARGET': '15.0',
      });
    });

    test('notices Swift packages of any kind', () {
      for (final isa in [
        'XCLocalSwiftPackageReference',
        'XCRemoteSwiftPackageReference',
        'XCSwiftPackageProductDependency',
      ]) {
        final withPackage = parseXcodeProject(
          _pbxproj.replaceFirst(
            '\t};\n\trootObject',
            '\t\tPK01 = {\n\t\t\tisa = $isa;\n\t\t};\n\t};\n\trootObject',
          ),
        );

        expect(withPackage!.usesSwiftPackages, isTrue, reason: isa);
      }
    });

    test('tolerates unusual objects', () {
      final odd = parseXcodeProject(
        _pbxproj
            .replaceFirst(
              'buildConfigurationList = CL01 /*',
              'x = y; z = CL01 /*',
            )
            .replaceFirst(
              'buildConfigurations = (\n\t\t\t\tCF00,',
              'buildConfigurations = (\n\t\t\t\tNOPE,',
            ),
      )!;

      expect(odd.targets.first.configurations, isEmpty);
      expect(odd.projectConfigurations.single.name, 'null');
    });

    test('tolerates a target list that is not a list', () {
      final project = parseXcodeProject(
        _pbxproj.replaceFirst(RegExp(r'targets = \([^)]*\);'), 'targets = x;'),
      )!;

      expect(project.targets, isEmpty);
    });

    test('tolerates a configuration list that is not a list', () {
      final project = parseXcodeProject(
        _pbxproj.replaceFirst(
          RegExp(r'buildConfigurations = \(\n\t\t\t\tCF00,\n\t\t\t\);'),
          'buildConfigurations = x;',
        ),
      )!;

      expect(project.projectConfigurations, isEmpty);
    });

    test('tolerates build settings that are not a dictionary', () {
      final project = parseXcodeProject(
        _pbxproj.replaceFirst(
          RegExp(r'buildSettings = \{[^}]*\};'),
          'buildSettings = x;',
        ),
      )!;

      expect(project.projectConfigurations.single.settings, isEmpty);
    });
  });

  group('parseXcodeProject with build phases and groups', () {
    final project = parseXcodeProject(_phases)!;
    final runner = project.appTarget!;

    test('reads the Run Script phases, unnamed or without a script', () {
      expect(runner.scriptPhases, [
        XcodeScriptPhase('Run Script', '$_backend build\n'),
        XcodeScriptPhase('Run Script', 'cp a b\n'),
        XcodeScriptPhase('[CP] Embed Pods Frameworks', ''),
      ]);
      expect(runner.scriptPhases.map((phase) => phase.isFlutter), [
        true,
        false,
        false,
      ]);
      expect(runner.scriptPhases.map((phase) => phase.isCocoaPods), [
        false,
        false,
        true,
      ]);
    });

    test('reads the resources by path through the groups, skipping what '
        "is not in the project's folder", () {
      expect(runner.resources, [
        'Runner/Assets.xcassets',
        'Runner/LaunchScreen.storyboard',
        'Config/GoogleService-Info.plist',
        'Loose.json',
      ]);
    });

    test('reads the .xcconfig a configuration is based on', () {
      expect(
        runner.configurations.first.baseConfiguration,
        'Flutter/devRelease.xcconfig',
      );
      expect(runner.configurations[1].baseConfiguration, isNull);
      expect(project.baseConfigurationsOf(runner, 'Release-dev'), [
        'Project.xcconfig',
        'Flutter/devRelease.xcconfig',
      ]);
      expect(project.baseConfigurationsOf(runner, 'Release-Staging'), isEmpty);
    });

    test('layeredSettingsOf puts each layer over the one before', () {
      expect(
        project.layeredSettingsOf(runner, 'Release-dev', {
          'Project.xcconfig': {
            'SHARED': 'project file',
            'ONLY_PROJECT': 'project file',
            'PROJECT_FILE': 'yes',
          },
          'Flutter/devRelease.xcconfig': {
            'SHARED': 'target file',
            'ONLY_PROJECT': 'target file',
            'ASSET_PREFIX': 'dev',
          },
        }),
        {
          'SHARED': 'target',
          'ONLY_PROJECT': 'target file',
          'PROJECT_FILE': 'yes',
          'ASSET_PREFIX': 'dev',
        },
      );
      expect(project.layeredSettingsOf(runner, 'Release-dev', {}), {
        'SHARED': 'target',
        'ONLY_PROJECT': 'project',
      });
      expect(project.layeredSettingsOf(runner, 'Release-nope', {}), isEmpty);
    });

    test('releaseConfigurationsFor matches as flutter build does', () {
      expect(project.releaseConfigurationsFor(runner, 'dev'), ['Release-dev']);
      expect(project.releaseConfigurationsFor(runner, 'DEV'), ['Release-dev']);
      expect(project.releaseConfigurationsFor(runner, 'Staging'), [
        'Release-Staging',
      ]);
      expect(project.releaseConfigurationsFor(runner, 'staging'), [
        'Release-Staging',
        'Release-STAGING',
      ]);
      expect(project.releaseConfigurationsFor(runner, 'prod'), isEmpty);
      expect(project.releaseConfigurationsFor(runner, null), isEmpty);
    });

    test('releaseConfigurationsFor without a flavor is Release', () {
      final plain = parseXcodeProject(_pbxproj)!;

      expect(plain.releaseConfigurationsFor(plain.appTarget!, null), [
        'Release',
      ]);
    });

    test('gives up on groups that hold each other', () {
      final looped = parseXcodeProject(
        _phases
            .replaceFirst(
              'children = ( G1, G2, G3 ); sourceTree',
              'children = ( G1, G2, G3 ); path = top; sourceTree',
            )
            .replaceFirst(
              'G1 = { isa = PBXGroup; children = ( F1, V1, F8 );',
              'G1 = { isa = PBXGroup; children = ( F1, V1, F8, G0 );',
            ),
      )!;

      expect(looped.appTarget!.resources, [
        'Config/GoogleService-Info.plist',
        'Loose.json',
      ]);
    });
  });

  group('parseXcconfig', () {
    test('reads includes and settings, without comments or conditions', () {
      final xcconfig = parseXcconfig('''
#include? "Pods/Target Support Files/Pods-Runner/Pods-Runner.release.xcconfig"
#include "Generated.xcconfig"
// A comment.
FLUTTER_TARGET=lib/main_dev.dart
ASSET_PREFIX = dev ;
BUNDLE_DISPLAY_NAME = Shop Dev // shown under the icon
OTHER_LDFLAGS[sdk=iphoneos*] = -ObjC

not a setting
''');

      expect(xcconfig.includes, [
        'Pods/Target Support Files/Pods-Runner/Pods-Runner.release.xcconfig',
        'Generated.xcconfig',
      ]);
      expect(xcconfig.settings, {
        'FLUTTER_TARGET': 'lib/main_dev.dart',
        'ASSET_PREFIX': 'dev',
        'BUNDLE_DISPLAY_NAME': 'Shop Dev',
      });
    });
  });

  group('expandBuildSetting', () {
    test(r'replaces $(NAME) and ${NAME}, nested too', () {
      expect(
        expandBuildSetting(r'AppIcon-$(ASSET_PREFIX)${SUFFIX}', {
          'ASSET_PREFIX': r'$(FLAVOR)',
          'FLAVOR': 'dev',
          'SUFFIX': '-x',
        }),
        'AppIcon-dev-x',
      );
    });

    test(r'leaves $(inherited) empty and an unknown reference as it is', () {
      expect(
        expandBuildSetting(r'$(inherited)AppIcon$(UNKNOWN)', {}),
        r'AppIcon$(UNKNOWN)',
      );
      expect(expandBuildSetting('AppIcon', {}), 'AppIcon');
    });
  });

  group('parseXcodeProject on text that is not a project', () {
    for (final entry in {
      'empty': '',
      'a bare word': 'hello',
      'an array': '(a, b)',
      'trailing text': '{ objects = {}; rootObject = X; } extra',
      'an unterminated string': '{ a = "oops; }',
      'a missing equals sign': '{ a b; }',
      'a missing semicolon': '{ a = b }',
      'an unexpected character': '{ a = ; }',
      'an unclosed dictionary': '{ a = b;',
      'a stray bracket': '{ a = ); }',
      'no objects': '{ rootObject = X; }',
      'objects that are not a dictionary': '{ objects = x; rootObject = X; }',
      'no root object': '{ objects = {}; rootObject = X; }',
      'a root object that is not a dictionary':
          '{ objects = { X = y; }; rootObject = X; }',
    }.entries) {
      test('is null for ${entry.key}', () {
        expect(parseXcodeProject(entry.value), isNull);
      });
    }

    test('skips comments of both kinds, even unterminated', () {
      const text = '''
// header
{ /* c */ objects = { P = { isa = PBXProject; }; }; rootObject = P; // end
} /* never closed''';

      expect(parseXcodeProject(text)!.targets, isEmpty);
    });

    test('reads a trailing backslash in a string', () {
      expect(parseXcodeProject(r'{ a = "x\'), isNull);
    });
  });

  test('value classes compare by value', () {
    XcodeBuildConfiguration configuration() =>
        XcodeBuildConfiguration('a', {'k': 'v'});
    XcodeTarget target() => XcodeTarget(
      name: 'a',
      productType: 'p',
      configurations: [configuration()],
    );
    XcodeProject project() => XcodeProject(
      targets: [target()],
      projectConfigurations: [configuration()],
      usesSwiftPackages: false,
    );

    XcodeScriptPhase phase() => XcodeScriptPhase('a', 'b');
    Xcconfig xcconfig() => Xcconfig(includes: ['a'], settings: {'k': 'v'});

    expect(configuration(), configuration());
    expect(target(), target());
    expect(project(), project());
    expect(phase(), phase());
    expect(xcconfig(), xcconfig());
    expect(configuration(), isNot(const XcodeBuildConfiguration('b', {})));
    expect(
      configuration(),
      isNot(XcodeBuildConfiguration('a', {'k': 'v'}, baseConfiguration: 'x')),
    );
  });

  test("a script phase is not Flutter's with no command or another one", () {
    expect(XcodeScriptPhase('Run Script', '').isFlutter, isFalse);
    expect(
      XcodeScriptPhase(
        'Thin Binary',
        '# Flutter\n\n  $_backend embed_and_thin\n',
      ).isFlutter,
      isTrue,
    );
    expect(
      XcodeScriptPhase(
        'Run Script',
        'cp GoogleService-Info.plist .\n$_backend build\n',
      ).isFlutter,
      isFalse,
    );
  });
}

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

    expect(configuration(), configuration());
    expect(target(), target());
    expect(project(), project());
    expect(configuration(), isNot(const XcodeBuildConfiguration('b', {})));
  });
}

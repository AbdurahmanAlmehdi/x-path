// Equal constants are identical and never compare props, so these tests
// build their values at run time.
// ignore_for_file: prefer_const_constructors

import 'package:test/test.dart';
import 'package:xp_engine/src/scan/gradle_parser.dart';

void main() {
  group('parseGradle', () {
    test('reads Groovy flavors as flutter_flavorizr writes them', () {
      final info = parseGradle('''
android {
    flavorDimensions += "flavor-type"

    productFlavors {
        dev {
            dimension "flavor-type"
            applicationId "com.example.dev"
            resValue "string", "app_name", "Example Dev"
        }
        prod {
            dimension "flavor-type"
            applicationId "com.example"
        }
    }
}
''');

      expect(info.flavors, const [
        GradleFlavor(
          'dev',
          dimension: 'flavor-type',
          applicationId: 'com.example.dev',
        ),
        GradleFlavor(
          'prod',
          dimension: 'flavor-type',
          applicationId: 'com.example',
        ),
      ]);
      expect(info.mentionsProductFlavors, isTrue);
      expect(info.dimensions, {'flavor-type'});
    });

    test('reads Kotlin flavors created with create, register and quotes', () {
      final info = parseGradle('''
android.apply {
    productFlavors {
        create("dev") {
            dimension = "flavor-type"
            applicationId = "com.example.dev"
            resValue(type = "string", name = "app_name", value = "Dev")
        }
        register('qa') {
            applicationId = 'com.example.qa'
        }
        "prod" {
            applicationId = "com.example"
        }
    }
}
''');

      expect(info.flavors.map((flavor) => flavor.name), ['dev', 'qa', 'prod']);
      expect(info.flavors[1].applicationId, 'com.example.qa');
    });

    test('ignores nested blocks and blocks that name no flavor', () {
      final info = parseGradle('''
productFlavors {
    dev {
        manifestPlaceholders = [applicationId: "not.this"]
        buildConfigField { applicationId "nor.this" }
        applicationId "com.example.dev"
    }
    ext.something { applicationId "x" }
}
''');

      expect(info.flavors.single.name, 'dev');
      expect(info.flavors.single.applicationId, 'com.example.dev');
    });

    test('keeps the suffix apart from the id', () {
      final info = parseGradle('''
defaultConfig {
    applicationId "com.example"
}
productFlavors {
    dev {
        applicationIdSuffix ".dev"
    }
    prod {
    }
    own {
        applicationId "com.other"
        applicationIdSuffix ".x"
    }
}
''');

      expect(info.defaultApplicationId, 'com.example');
      expect(info.flavors[0].applicationId, isNull);
      expect(info.flavors[0].applicationIdSuffix, '.dev');
      expect(info.applicationIdOf(info.flavors[0]), 'com.example.dev');
      expect(info.applicationIdOf(info.flavors[1]), 'com.example');
      expect(info.applicationIdOf(info.flavors[2]), 'com.other.x');
    });

    test('has no application id without a default and an own id', () {
      final info = parseGradle('productFlavors { dev { } }');

      expect(info.applicationIdOf(info.flavors.single), isNull);
    });

    test('ignores comments but not strings that look like them', () {
      final info = parseGradle(r'''
// productFlavors { ghost { applicationId "ghost" } }
/* defaultConfig { applicationId "block" } */
defaultConfig {
    applicationId "https://not-a-comment" // trailing
    description "quote \" inside"
}
productFlavors {
    real { applicationId 'com.real' }
}
/* unterminated''');

      expect(info.flavors.map((flavor) => flavor.name), ['real']);
      expect(info.defaultApplicationId, 'https://not-a-comment');
    });

    test('finds the keystore properties reference', () {
      expect(
        parseGradle('val f = rootProject.file("key.properties")')
            .keyPropertiesReference,
        'key.properties',
      );
      expect(
        parseGradle("file('../secrets/key.properties')").keyPropertiesReference,
        '../secrets/key.properties',
      );
      expect(parseGradle('android { }').keyPropertiesReference, isNull);
    });

    test('says when productFlavors is there but unreadable', () {
      final info = parseGradle('productFlavors { somethingElse() }');

      expect(info.mentionsProductFlavors, isTrue);
      expect(info.flavors, isEmpty);
    });

    test('copes with an unbalanced block', () {
      final info = parseGradle('productFlavors { dev { applicationId "a"');

      expect(info.flavors.single.name, 'dev');
    });

    test('has nothing in an empty script', () {
      final info = parseGradle('');

      expect(info.mentionsProductFlavors, isFalse);
      expect(info.flavors, isEmpty);
      expect(info.defaultApplicationId, isNull);
    });
  });

  group('GradleInfo.merge', () {
    test('joins flavors by name and fills what one leaves unset', () {
      final main = parseGradle('''
defaultConfig { applicationId "com.example" }
android { key = "key.properties" }
''');
      final flavorizr = parseGradle('''
productFlavors {
    dev { applicationId "com.example.dev" }
}
''');
      final more = parseGradle('''
productFlavors {
    dev { dimension "d" }
    prod { applicationId "com.example" }
}
''');

      final merged = main.merge(flavorizr).merge(more);

      expect(merged.defaultApplicationId, 'com.example');
      expect(merged.keyPropertiesReference, 'key.properties');
      expect(merged.mentionsProductFlavors, isTrue);
      expect(merged.flavors, const [
        GradleFlavor('dev', dimension: 'd', applicationId: 'com.example.dev'),
        GradleFlavor('prod', applicationId: 'com.example'),
      ]);
    });

    test('keeps what the first has', () {
      final first = parseGradle('defaultConfig { applicationId "a" }');
      final second = parseGradle('defaultConfig { applicationId "b" }');

      expect(first.merge(second).defaultApplicationId, 'a');
    });
  });

  test('GradleFlavor and GradleInfo compare by value', () {
    GradleFlavor flavor() => GradleFlavor('a', dimension: 'd');
    GradleInfo info() => GradleInfo(flavors: [flavor()]);

    expect(flavor(), flavor());
    expect(flavor(), isNot(const GradleFlavor('b')));
    expect(info(), info());
    expect(info(), isNot(const GradleInfo()));
  });
}

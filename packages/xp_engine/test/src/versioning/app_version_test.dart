import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  group('VersionName', () {
    test('parses x.y.z and prints it back', () {
      final version = VersionName.parse('5.4.1');

      expect(version, const VersionName(5, 4, 1));
      expect('$version', '5.4.1');
    });

    test('compares number by number, not as text', () {
      expect(VersionName.parse('5.10.0') > VersionName.parse('5.9.9'), isTrue);
      expect(VersionName.parse('6.0.0') > VersionName.parse('5.99.99'), isTrue);
      expect(VersionName.parse('5.4.2') > VersionName.parse('5.4.1'), isTrue);
      expect(VersionName.parse('5.4.1') > VersionName.parse('5.4.1'), isFalse);
      expect(VersionName.parse('5.4.0') > VersionName.parse('5.4.1'), isFalse);
      expect(
        VersionName.parse('5.4.1').compareTo(VersionName.parse('5.4.1')),
        0,
      );
    });

    test('rejects anything but three numbers', () {
      for (final text in ['', '5', '5.4', '5.4.1.2', '5.4.x', '1.0.0-beta']) {
        expect(
          () => VersionName.parse(text),
          throwsA(isA<FormatException>()),
          reason: text,
        );
      }
    });
  });

  group('AppVersion', () {
    test('parses x.y.z+build', () {
      final version = AppVersion.parse('5.4.1+3283');

      expect(version.name, const VersionName(5, 4, 1));
      expect(version.build, 3283);
      expect('$version', '5.4.1+3283');
    });

    test('parses a version without a build', () {
      final version = AppVersion.parse('1.0.0');

      expect(version.build, isNull);
      expect('$version', '1.0.0');
    });

    test('rejects a build that is not a number', () {
      for (final text in ['1.0.0+', '1.0.0+x', '1.0.0+1+2', '1.0+3']) {
        expect(
          () => AppVersion.parse(text),
          throwsA(isA<FormatException>()),
          reason: text,
        );
      }
    });
  });
}

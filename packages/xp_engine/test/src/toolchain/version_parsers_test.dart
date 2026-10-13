import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

import 'fixtures.dart';

void main() {
  group('parseGhVersion', () {
    test('reads the captured output', () {
      expect(parseGhVersion(fixture('gh_version.txt')), '2.96.0');
    });

    test('reads a pre-release', () {
      expect(
        parseGhVersion('gh version 2.97.0-rc.1 (2026-08-01)\n'),
        '2.97.0-rc.1',
      );
    });

    test('is null for anything else', () {
      expect(parseGhVersion(''), isNull);
      expect(parseGhVersion('command not found: gh'), isNull);
    });
  });

  group('parseShorebirdVersion', () {
    test('reads the first line of the banner', () {
      expect(
        parseShorebirdVersion(fixture('shorebird_version.txt')),
        '1.6.128',
      );
    });

    test('ignores lines before the banner', () {
      expect(
        parseShorebirdVersion(
          'A new version is available\nShorebird 1.7.0 • x\n',
        ),
        '1.7.0',
      );
    });

    test('is null for anything else', () {
      expect(parseShorebirdVersion('Flutter 3.41.5 • revision abc'), isNull);
      expect(parseShorebirdVersion(''), isNull);
    });
  });

  group('parseXcodeVersion', () {
    test('reads the version and build of the captured output', () {
      expect(parseXcodeVersion(fixture('xcodebuild_version.txt')), (
        version: '27.1',
        build: '27A9275',
      ));
    });

    test('reads a version without a build', () {
      expect(parseXcodeVersion('Xcode 16\n'), (version: '16', build: null));
    });

    test('is null for the error of the command line tools', () {
      expect(
        parseXcodeVersion(
          'xcode-select: error: tool xcodebuild requires Xcode, but active '
          'developer directory /Library/Developer/CommandLineTools is a '
          'command line tools instance',
        ),
        isNull,
      );
    });
  });

  group('parseFlutterMachineVersion', () {
    test('reads the captured output', () {
      expect(
        parseFlutterMachineVersion(fixture('flutter_version_machine.json')),
        (flutter: '3.47.6', dart: '3.13.5'),
      );
    });

    test('skips progress lines before the JSON', () {
      expect(
        parseFlutterMachineVersion(
          'Building flutter tool...\nDownloading Dart SDK...\n'
          '{"frameworkVersion": "3.47.6", "dartSdkVersion": "3.13.5"}\n',
        ),
        (flutter: '3.47.6', dart: '3.13.5'),
      );
    });

    test('accepts flutterVersion and a missing Dart version', () {
      expect(parseFlutterMachineVersion('{"flutterVersion": "3.47.6"}'), (
        flutter: '3.47.6',
        dart: null,
      ));
    });

    test('is null for anything that is not a Flutter version', () {
      expect(parseFlutterMachineVersion(''), isNull);
      expect(parseFlutterMachineVersion('{"a": '), isNull);
      expect(parseFlutterMachineVersion('{not json}'), isNull);
      expect(parseFlutterMachineVersion('[1]'), isNull);
      expect(parseFlutterMachineVersion('{"frameworkVersion": 3}'), isNull);
      expect(parseFlutterMachineVersion('{"frameworkVersion": ""}'), isNull);
      expect(parseFlutterMachineVersion('} {'), isNull);
    });
  });

  group('parseFvmList', () {
    test(
      'reads the output of fvm 3, which does not name the Flutter version',
      () {
        expect(parseFvmList(fixture('fvm_3.2.1_api_list.json')), [
          (
            name: '3.47.6',
            directory: '/Users/dev/fvm/versions/3.47.6',
            flutterVersion: null,
            dartVersion: '3.13.5',
          ),
          (
            name: '3.47.4',
            directory: '/Users/dev/fvm/versions/3.47.4',
            flutterVersion: null,
            dartVersion: '3.13.3',
          ),
        ]);
      },
    );

    test('reads the output of fvm 4', () {
      final versions = parseFvmList(fixture('fvm_4.0.5_api_list.json'))!;

      expect(versions.map((v) => v.name), ['3.47.6', '3.47.4']);
      expect(versions.first.flutterVersion, '3.47.6');
      expect(versions.first.dartVersion, '3.13.5');
    });

    test('keeps entries without versions and skips broken ones', () {
      expect(
        parseFvmList(
          '{"versions": [{"name": "stable", "directory": "/d"}, '
          '{"name": "beta"}, 3]}',
        ),
        [
          (
            name: 'stable',
            directory: '/d',
            flutterVersion: null,
            dartVersion: null,
          ),
        ],
      );
    });

    test('is null when there is no list', () {
      expect(parseFvmList(''), isNull);
      expect(parseFvmList('{"size": "1 GB"}'), isNull);
      expect(parseFvmList('{"versions": {}}'), isNull);
    });
  });
}

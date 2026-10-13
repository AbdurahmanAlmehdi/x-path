import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  group('InMemoryScanSource', () {
    final source = InMemoryScanSource({
      'pubspec.yaml': 'name: a',
      'lib/main.dart': 'void main() {}',
      'lib/src/util.dart': '',
      'android/app/build.gradle': '',
    });

    test('exists for files and for directories above them', () async {
      expect(await source.exists('pubspec.yaml'), isTrue);
      expect(await source.exists('lib'), isTrue);
      expect(await source.exists('lib/src'), isTrue);
      expect(await source.exists(''), isTrue);
      expect(await source.exists('ios'), isFalse);
      expect(await source.exists('lib/ma'), isFalse);
    });

    test('reads files and nothing else', () async {
      expect(await source.read('pubspec.yaml'), 'name: a');
      expect(await source.read('lib'), isNull);
      expect(await source.read('missing'), isNull);
    });

    test('lists direct children, sorted, files and directories', () async {
      expect(await source.list(''), const [
        ScanEntry('android', isDirectory: true),
        ScanEntry('lib', isDirectory: true),
        ScanEntry('pubspec.yaml', isDirectory: false),
      ]);
      expect(await source.list('lib'), const [
        ScanEntry('main.dart', isDirectory: false),
        ScanEntry('src', isDirectory: true),
      ]);
    });

    test('lists nothing for a directory that does not exist', () async {
      expect(await source.list('ios'), isEmpty);
      expect(await source.list('lib/ma'), isEmpty);
    });

    test('does not change when the map it was built from does', () async {
      final files = {'a': '1'};
      final copy = InMemoryScanSource(files);
      files['b'] = '2';

      expect(await copy.exists('b'), isFalse);
    });
  });

  test('ScanEntry compares by value', () {
    expect(
      const ScanEntry('a', isDirectory: true),
      const ScanEntry('a', isDirectory: true),
    );
    expect(
      const ScanEntry('a', isDirectory: true),
      isNot(const ScanEntry('a', isDirectory: false)),
    );
  });

  group('joinScanPath', () {
    test('joins with a slash', () {
      expect(joinScanPath('apps/a', 'lib'), 'apps/a/lib');
    });

    test('leaves out the root and the empty part', () {
      expect(joinScanPath('', 'lib'), 'lib');
      expect(joinScanPath('.', 'lib'), 'lib');
      expect(joinScanPath('apps/a', ''), 'apps/a');
    });
  });

  group('normalizeScanPath', () {
    test('resolves dots and doubled slashes', () {
      expect(normalizeScanPath('a/./b//c'), 'a/b/c');
      expect(normalizeScanPath('a/b/../c'), 'a/c');
    });

    test('never climbs above the root', () {
      expect(normalizeScanPath('../../a'), 'a');
      expect(normalizeScanPath(''), '');
    });
  });
}

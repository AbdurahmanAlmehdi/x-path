import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  group('isExactFlutterVersion', () {
    test('accepts releases', () {
      for (final version in ['3.47.6', '3.0.0', '3.47.0-0.1.pre', '3.47.6+1']) {
        expect(isExactFlutterVersion(version), isTrue, reason: version);
      }
    });

    test('rejects channels, ranges and anything unsafe', () {
      for (final version in [
        'stable',
        '3.47',
        '3.47.x',
        '^3.47.6',
        '--upload-pack=x',
        '3.47.6/../..',
        '3.47.6 ',
        '',
      ]) {
        expect(isExactFlutterVersion(version), isFalse, reason: version);
      }
    });
  });

  group('isFlutterPinName', () {
    test('accepts versions and channels', () {
      for (final pin in ['3.47.6', 'stable', 'beta', '3.47.0-0.1.pre']) {
        expect(isFlutterPinName(pin), isTrue, reason: pin);
      }
    });

    test('rejects options, paths and spaces', () {
      for (final pin in ['-h', '--version', '../x', 'a/b', 'a b', '', '.x']) {
        expect(isFlutterPinName(pin), isFalse, reason: pin);
      }
    });
  });
}

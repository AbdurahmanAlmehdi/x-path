import 'package:test/test.dart';
import 'package:xp_engine/src/workflows/suggestion.dart';

void main() {
  group('closestTo', () {
    test('finds a typo or another case of a known name', () {
      expect(
        closestTo('firebaseAppId', ['firebaseAppIds', 'notes']),
        'firebaseAppIds',
      );
      expect(closestTo('hasIOS', ['hasIos', 'hasAndroid']), 'hasIos');
      expect(closestTo('stage', ['stages', 'name']), 'stages');
    });

    test('finds nothing far, nothing in an empty list, and not the name', () {
      expect(closestTo('lasers', ['android', 'flutter']), isNull);
      expect(closestTo('ab', ['cd']), isNull);
      expect(closestTo('x', const []), isNull);
      expect(closestTo('same', ['same']), isNull);
    });

    test('allows more edits in a longer name', () {
      expect(closestTo('abc', ['abd']), 'abd');
      expect(closestTo('abc', ['xyc']), isNull);
      expect(closestTo('abcdef', ['abcxyf']), 'abcxyf');
      expect(closestTo('abcdefghij', ['abcdefgxyz']), 'abcdefgxyz');
    });
  });

  group('suggestion', () {
    test('names the one meant, with its prefix', () {
      expect(
        suggestion('firebaseAppId', ['firebaseAppIds'], prefix: 'inputs.'),
        'Did you mean "inputs.firebaseAppIds"?',
      );
    });

    test('else lists the known ones, sorted, under its label', () {
      expect(
        suggestion('lasers', ['flutter', 'android']),
        'Allowed: android, flutter.',
      );
      expect(
        suggestion('web', ['ios', 'android'], prefix: 'f.', label: 'It has'),
        'It has: f.android, f.ios.',
      );
    });

    test('says nothing when nothing is known', () {
      expect(suggestion('x', const []), isNull);
    });
  });
}

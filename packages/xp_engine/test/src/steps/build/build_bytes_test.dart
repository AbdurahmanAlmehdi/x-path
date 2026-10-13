import 'dart:convert';

import 'package:test/test.dart';
import 'package:xp_engine/src/steps/build/bytes_finder.dart';
import 'package:xp_engine/src/steps/build/dart_defines.dart';

void main() {
  group('BytesFinder', () {
    BytesFinder finder(List<String> needles) =>
        BytesFinder([for (final needle in needles) utf8.encode(needle)]);

    List<String> missing(BytesFinder finder) => [
      for (final bytes in finder.missing) utf8.decode(bytes),
    ];

    test('finds a needle inside a chunk', () {
      final found = finder(['host.io'])..add(utf8.encode('xx host.io yy'));

      expect(missing(found), isEmpty);
    });

    test('finds a needle that spans chunks', () {
      final found = finder(['abcabd'])
        ..add(utf8.encode('xxabcab'))
        ..add(utf8.encode('cabd'));

      expect(missing(found), isEmpty);
    });

    test('backs off after a partial match', () {
      final found = finder(['aab'])..add(utf8.encode('aaaab'));

      expect(missing(found), isEmpty);
    });

    test('reports the needles that were not found, in order', () {
      final found = finder(['one', 'two', 'three'])..add(utf8.encode('two'));

      expect(missing(found), ['one', 'three']);
    });

    test('does not find a near miss', () {
      final found = finder(['abc'])..add(utf8.encode('ab_abd'));

      expect(missing(found), ['abc']);
    });

    test('stops looking once found', () {
      final found = finder(['a'])
        ..add(utf8.encode('a'))
        ..add(utf8.encode('zzz'));

      expect(missing(found), isEmpty);
    });
  });

  group('parseDartDefines', () {
    test('reads a JSON object of scalars', () {
      expect(parseDartDefines('{"A": "x", "B": 2, "C": true}'), {
        'A': 'x',
        'B': '2',
        'C': 'true',
      });
    });

    test('rejects JSON that is not flat', () {
      for (final bad in [
        '{"A": {"b": 1}}',
        '{"A": [1]}',
        '{"A": 1',
        '{ [] }',
      ]) {
        expect(() => parseDartDefines(bad), throwsFormatException);
      }
    });

    test('reads KEY=value lines, first one wins, quotes dropped', () {
      expect(
        parseDartDefines(
          '# comment\n\n  A = "https://x.io/p"\nA=other\nnoequals\n=empty\nB=2\n',
        ),
        {'A': 'https://x.io/p', 'B': '2'},
      );
    });
  });

  group('compiledNeedle', () {
    test('keeps the host of a URL', () {
      expect(compiledNeedle('https://api.x.io/v1/'), 'api.x.io');
      expect(compiledNeedle('http://api.x.io'), 'api.x.io');
    });

    test('keeps any other value', () {
      expect(compiledNeedle('prod'), 'prod');
      expect(compiledNeedle(''), '');
    });
  });
}

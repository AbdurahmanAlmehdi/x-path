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

    test('reads KEY=value lines as Flutter does', () {
      expect(
        parseDartDefines(
          '# comment\n\n'
          '  A = "https://x.io/p"\n'
          'A=last wins\n'
          'B="two words" # note\n'
          "C='it is'\n"
          'D=`x y`\n'
          'E=plain # note\n'
          'F=\n'
          'G=   \n'
          'H=""\n'
          'I="p"s"w"\n'
          'J=a#b\n',
        ),
        {
          'A': 'last wins',
          'B': 'two words',
          'C': 'it is',
          'D': 'x y',
          'E': 'plain',
          'F': '',
          'G': '',
          'H': '',
          'I': 'p"s"w',
          'J': 'a',
        },
      );
    });

    test('refuses what Flutter refuses, without quoting the file', () {
      for (final bad in const [
        '{"A": {"secret-value": 1}}',
        '{"A": "secret-value"',
        'A=x\nsecret-value\n',
        '=secret-value\n',
        'export A=secret-value\n',
        'A-B=secret-value\n',
        'A="""secret-value\n',
      ]) {
        expect(
          () => parseDartDefines(bad),
          throwsA(
            isA<FormatException>().having(
              (error) => error.toString(),
              'text',
              isNot(contains('secret-value')),
            ),
          ),
          reason: bad,
        );
      }
    });
  });

  group('checkDartDefines', () {
    test('takes a file with a value, and an empty value is one', () {
      checkDartDefines('{"A": "x"}');
      checkDartDefines('# comment\n\nA=\n');
    });

    test('refuses a file that defines nothing', () {
      for (final empty in const ['{}', '# only a comment\n', '\n']) {
        expect(() => checkDartDefines(empty), throwsFormatException);
      }
    });
  });

  group('dartDefineSecrets', () {
    test('names the file, each value and each entry as Flutter encodes it', () {
      const text = 'API_KEY="k 12345"\n';

      expect(dartDefineSecrets(text), [
        text,
        'k 12345',
        base64.encode(utf8.encode('API_KEY=k 12345')),
      ]);
    });

    test('names the value Flutter compiles of a key defined twice', () {
      expect(dartDefineSecrets('A=first1\nA=second2\n'), contains('second2'));
    });

    test('names only the text of a file it cannot read', () {
      expect(dartDefineSecrets('{"A": {"b": 1}}'), ['{"A": {"b": 1}}']);
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

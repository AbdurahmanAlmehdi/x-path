import 'package:test/test.dart';
import 'package:xp_repositories/xp_repositories.dart';

void main() {
  const scope = <String, Object?>{
    'platform': 'ios',
    'flavors': ['dev', 'prod'],
    'flavor': {
      'name': 'prod',
      'shorebird': true,
      'credentials': {'play_sa': true},
    },
    'inputs': {
      'appleAppIds': {'prod': '123'},
    },
    'zero': 0,
    'empty': '',
  };

  Object? eval(String source) => evaluateExpression(source, scope);

  group('evaluateExpression', () {
    test('reads literals', () {
      expect(eval('true'), isTrue);
      expect(eval('false'), isFalse);
      expect(eval('null'), isNull);
      expect(eval('42'), 42);
      expect(eval("'it''s'"), "it's");
      expect(eval('"a"'), 'a');
    });

    test('reads names, keys and items', () {
      expect(eval('platform'), 'ios');
      expect(eval('flavor.name'), 'prod');
      expect(eval("flavor['shorebird']"), isTrue);
      expect(eval('flavors[1]'), 'prod');
      expect(eval('flavors[2]'), isNull);
      expect(eval('platform.name'), isNull);
      expect(eval('missing.a.b'), isNull);
      expect(eval('inputs.appleAppIds[flavor.name]'), '123');
      expect(eval('flavor.credentials.play_sa'), isTrue);
    });

    test('compares, negates and picks operands', () {
      expect(eval("platform == 'ios'"), isTrue);
      expect(eval("platform != 'ios'"), isFalse);
      expect(eval('!flavor.shorebird'), isFalse);
      expect(eval('!zero'), isTrue);
      expect(eval("empty || 'x'"), 'x');
      expect(eval("platform || 'x'"), 'ios');
      expect(eval("zero && 'x'"), 0);
      expect(eval("platform && 'x'"), 'x');
      expect(
        eval(
          "(platform == 'android' && flavor.credentials.play_sa) || "
          '(platform == "ios" && inputs.appleAppIds[flavor.name])',
        ),
        '123',
      );
    });

    test('refuses text that is not an expression', () {
      for (final source in [
        '',
        'a =',
        "'open",
        'a.',
        'a.1',
        'a[0',
        '(a',
        'a b',
        '&&',
        r'$',
      ]) {
        expect(
          () => eval(source),
          throwsA(isA<FormatException>()),
          reason: source,
        );
      }
    });
  });

  group('isTruthy', () {
    test('is false only for null, false, 0 and empty text', () {
      expect([null, false, 0, ''].any(isTruthy), isFalse);
      expect(
        [true, 1, 'a', <Object>[], <String, Object>{}].every(isTruthy),
        isTrue,
      );
    });
  });

  group('renderTemplate', () {
    test('keeps text without placeholders', () {
      expect(renderTemplate('plain', scope), 'plain');
      expect(renderTemplate('', scope), '');
    });

    test('keeps the type of a single placeholder', () {
      expect(renderTemplate(r'${{ flavors }}', scope), ['dev', 'prod']);
    });

    test('writes values into text', () {
      expect(
        renderTemplate(r'Build ${{ flavor.name }} for ${{ platform }}', scope),
        'Build prod for ios',
      );
      expect(
        renderTemplate(
          [
            r'${{ missing }}',
            r'${{ zero }}',
            r'${{ flavor.shorebird }}',
            r'${{ flavors }}',
            r'${{ inputs.appleAppIds }}',
          ].join('|'),
          scope,
        ),
        '|0|true|["dev","prod"]|{"prod":"123"}',
      );
    });

    test('refuses a placeholder that is not closed or not valid', () {
      expect(
        () => renderTemplate(r'a ${{ b', scope),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => renderTemplate(r'${{ a = }}', scope),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

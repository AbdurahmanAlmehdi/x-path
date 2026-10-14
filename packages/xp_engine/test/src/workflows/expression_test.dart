import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  Object? evaluate(String source, [Map<String, Object?> scope = const {}]) =>
      Expression.parse(source).evaluate(scope);

  ExpressionException failure(String source) {
    try {
      Expression.parse(source);
    } on ExpressionException catch (error) {
      return error;
    }
    throw StateError('"$source" parsed.');
  }

  group('values', () {
    test('are literals', () {
      expect(evaluate("'android'"), 'android');
      expect(evaluate('"android"'), 'android');
      expect(evaluate('42'), 42);
      expect(evaluate('true'), isTrue);
      expect(evaluate('false'), isFalse);
      expect(evaluate('null'), isNull);
    });

    test('keep a doubled quote inside a string as one', () {
      expect(evaluate("'it''s'"), "it's");
      expect(evaluate('"say ""hi"""'), 'say "hi"');
    });

    test('read variables, and null for what is not there', () {
      expect(evaluate('platform', {'platform': 'ios'}), 'ios');
      expect(evaluate('missing'), isNull);
    });

    test('read keys with a dot or an index', () {
      final scope = {
        'flavor': {
          'name': 'dev',
          'ids': ['a', 'b'],
        },
        'inputs': {
          'ids': {
            'dev': {'android': '1:2'},
          },
        },
        'key': 'dev',
      };

      expect(evaluate('flavor.name', scope), 'dev');
      expect(evaluate("flavor['name']", scope), 'dev');
      expect(evaluate('flavor.ids[1]', scope), 'b');
      expect(evaluate('inputs.ids[key].android', scope), '1:2');
    });

    test('read null past a missing key, an odd holder or a bad index', () {
      final scope = {
        'list': [1, 2],
        'text': 'x',
        'below': -1,
      };

      expect(evaluate('missing.a.b'), isNull);
      expect(evaluate('text.length', scope), isNull);
      expect(evaluate('list[5]', scope), isNull);
      expect(evaluate('list[below]', scope), isNull);
      expect(evaluate("list['a']", scope), isNull);
    });
  });

  group('operators', () {
    test('compare by value', () {
      expect(evaluate("platform == 'ios'", {'platform': 'ios'}), isTrue);
      expect(evaluate("platform != 'ios'", {'platform': 'ios'}), isFalse);
      expect(evaluate('1 == 1'), isTrue);
      expect(
        evaluate('a == b', {
          'a': [1],
          'b': [1],
        }),
        isTrue,
      );
      expect(evaluate('null == missing'), isTrue);
      expect(evaluate("'1' == 1"), isFalse);
    });

    test('negate by truthiness', () {
      expect(evaluate('!true'), isFalse);
      expect(evaluate('!null'), isTrue);
      expect(evaluate("!''"), isTrue);
      expect(evaluate('!0'), isTrue);
      expect(evaluate("!'x'"), isFalse);
      expect(evaluate('!!list', {'list': <int>[]}), isTrue);
    });

    test('&& and || give one of their operands', () {
      expect(evaluate("a && 'x'", {'a': 1}), 'x');
      expect(evaluate("a && 'x'", {'a': 0}), 0);
      expect(evaluate("a || 'y'", {'a': ''}), 'y');
      expect(evaluate("a || 'y'", {'a': 'z'}), 'z');
      expect(evaluate("a && b || 'c'", {'a': true, 'b': 'b'}), 'b');
      expect(evaluate("a && b || 'c'", {'a': null, 'b': 'b'}), 'c');
    });

    test('short-circuit', () {
      // The right side would fail if it were read; there is nothing to fail,
      // so check the value taken instead.
      expect(evaluate("true || 'never'"), isTrue);
      expect(evaluate("false && 'never'"), isFalse);
    });

    test('bind && tighter than || and == tighter than &&', () {
      expect(evaluate('true || false && false'), isTrue);
      expect(evaluate('(true || false) && false'), isFalse);
      expect(evaluate("'a' == 'a' && 'b' != 'c'"), isTrue);
    });

    test('are chained from the left', () {
      expect(evaluate('1 == 1 == true'), isTrue);
    });
  });

  group('truthiness', () {
    test('is false for null, false, 0 and the empty string only', () {
      expect(Expression.isTruthy(null), isFalse);
      expect(Expression.isTruthy(false), isFalse);
      expect(Expression.isTruthy(0), isFalse);
      expect(Expression.isTruthy(''), isFalse);
      expect(Expression.isTruthy('0'), isTrue);
      expect(Expression.isTruthy(const []), isTrue);
      expect(Expression.isTruthy(1), isTrue);
    });
  });

  group('variables', () {
    test('lists the names an expression reads', () {
      expect(
        Expression.parse("platform == 'ios' && flavor.prod || inputs[key]")
            .variables,
        {'platform', 'flavor', 'inputs', 'key'},
      );
      expect(Expression.parse('!x').variables, {'x'});
      expect(Expression.parse('1').variables, isEmpty);
    });
  });

  group('errors', () {
    test('name the problem and where it is', () {
      expect(failure('').message, contains('empty'));
      expect(failure('   ').message, contains('empty'));
      expect(failure('a == ').offset, 5);
      expect(failure('a == ').message, contains('end of the expression'));
      expect(failure("'open").offset, 0);
      expect(failure("'open").message, contains('not closed'));
      expect(failure('a = b').message, contains('"=="'));
      expect(failure('a & b').message, contains('"&&"'));
      expect(failure('a | b').message, contains('"||"'));
      expect(failure('a # b').message, 'Unexpected "#".');
      expect(failure('a b').message, contains('the name "b"'));
      expect(failure('a b').offset, 2);
    });

    test('describe every token that is not expected', () {
      for (final (source, described) in [
        ('(a', 'Expected ")", not the end'),
        ('a.', 'Expected a name after "."'),
        ('a.1', 'not the number 1'),
        ('a[', 'Expected a value'),
        ('a[1', 'Expected "]", not the end'),
        ('a)', 'Unexpected ")"'),
        ('a ]', 'Unexpected "]"'),
        ('== a', 'Expected a value, not "=="'),
        ('!= a', 'Expected a value, not "!="'),
        ('&& a', 'Expected a value, not "&&"'),
        ('|| a', 'Expected a value, not "||"'),
        ('a (b)', 'Unexpected "("'),
        ('a.[1]', 'not "["'),
        ('a. .b', 'not "."'),
        ("a 'x'", 'Unexpected a string'),
        ('a 3', 'Unexpected the number 3'),
        ('a !b', 'Unexpected "!"'),
        ('a != != b', 'Expected a value, not "!="'),
        ('a || || b', 'Expected a value, not "||"'),
      ]) {
        expect(failure(source).message, contains(described), reason: source);
      }
    });

    test('print the message and the offset', () {
      expect(
        const ExpressionException('m', 3).toString(),
        'ExpressionException: m (at 3)',
      );
    });
  });

  group('Template', () {
    Object? render(String source, [Map<String, Object?> scope = const {}]) =>
        Template.parse(source).evaluate(scope);

    test('is its text when it has no placeholder', () {
      final template = Template.parse('plain');

      expect(template.hasPlaceholders, isFalse);
      expect(template.isSinglePlaceholder, isFalse);
      expect(template.expressions, isEmpty);
      expect(template.evaluate(const {}), 'plain');
    });

    test('knows whether it is one placeholder', () {
      expect(Template.parse(r'${{ a }}').isSinglePlaceholder, isTrue);
      expect(Template.parse(r'x ${{ a }}').isSinglePlaceholder, isFalse);
      expect(Template.parse(r'${{ a }}${{ b }}').isSinglePlaceholder, isFalse);
    });

    test('keeps the type of a lone placeholder', () {
      expect(
        render(r'${{ platforms }}', {
          'platforms': ['a'],
        }),
        ['a'],
      );
      expect(
        render(r'${{flavor.prod}}', {
          'flavor': {'prod': true},
        }),
        isTrue,
      );
      expect(render(r'${{ missing }}'), isNull);
    });

    test('becomes text around text', () {
      expect(
        render(r'Build ${{ flavor.name }} for ${{ platform }}', {
          'flavor': {'name': 'dev'},
          'platform': 'ios',
        }),
        'Build dev for ios',
      );
      expect(render(r'a${{ missing }}b'), 'ab');
      expect(render(r'n=${{ 3 }}'), 'n=3');
      expect(render(r'${{ ok }} ${{ ok }}', {'ok': true}), 'true true');
      expect(
        render(r'x ${{ list }}', {
          'list': [1, 'a'],
        }),
        'x [1,"a"]',
      );
    });

    test('reads placeholders next to each other', () {
      expect(render(r'${{ a }}${{ b }}', {'a': 'x', 'b': 'y'}), 'xy');
    });

    test('says where a placeholder is wrong, in the text', () {
      expect(
        () => Template.parse(r'abc ${{ a == }}'),
        throwsA(
          isA<ExpressionException>().having((e) => e.offset, 'offset', 13),
        ),
      );
      expect(
        () => Template.parse(r'abc ${{ a'),
        throwsA(
          isA<ExpressionException>()
              .having((e) => e.offset, 'offset', 4)
              .having((e) => e.message, 'message', contains('not closed')),
        ),
      );
    });

    test('lists the expressions it holds', () {
      expect(
        Template.parse(r'${{ a }} and ${{ b.c }}').expressions
            .expand((e) => e.variables),
        ['a', 'b'],
      );
    });
  });
}

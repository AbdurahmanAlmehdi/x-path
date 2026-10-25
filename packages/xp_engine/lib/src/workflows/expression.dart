import 'dart:convert';

import 'package:collection/collection.dart';

/// An expression of a workflow is not valid. [offset] is the position of the
/// problem in the source text, from 0.
class ExpressionException implements Exception {
  /// Creates the exception.
  const new(this.message, this.offset);

  /// What is wrong.
  final String message;

  /// Where, in the source text.
  final int offset;

  @override
  String toString() => 'ExpressionException: $message (at $offset)';
}

/// A parsed expression of the small language of workflows.
///
/// The language reads values and compares them; it runs nothing. There is no
/// eval, no function call, no assignment, no loop:
///
/// ```text
/// platform == 'android' && flavor.prod
/// !flavor.shorebird || inputs.firebaseAppIds[flavor.name][platform]
/// ```
///
/// - Values are `null`, `true`, `false`, numbers, strings (`'x'` or `"x"`, a
///   doubled quote inside stands for one), lists and maps (the values of the
///   scope).
/// - A name reads a variable of the scope; `a.b` and `a['b']` read a key,
///   `a[0]` an item. Reading what is not there gives `null`, also past a
///   `null`, so `a.b.c` never fails.
/// - `==` and `!=` compare by value, `!` negates, `&&` and `||` short-circuit
///   and give one of their operands, so `a && b || c` picks between values.
/// - `null`, `false`, `0` and `''` are false; everything else is true.
sealed class Expression {
  const new();

  /// Reads [source].
  ///
  /// Throws an [ExpressionException] for text that is not an expression.
  factory parse(String source) => _Parser(source).parse();

  /// The value of the expression, reading variables from [scope].
  Object? evaluate(Map<String, Object?> scope);

  /// The variables the expression reads: the first name of each reference.
  Set<String> get variables;

  /// What the expression reads, each as the variable and the keys written
  /// out after it: `inputs.ids[flavor.name].android` reads `inputs.ids` and
  /// `flavor.name`.
  Set<String> get paths;

  /// The path of a reference whose keys are all written out, as in
  /// `flavor.credentials.play_sa`; `null` for anything else.
  String? get _chain => null;

  /// The expression as it reads, for example `flavor.credentials.play_sa`
  /// or `platform == 'ios'`.
  String get source;

  /// The parts that make the expression false in [scope]: the false
  /// operands of `&&` and `||` (both of a false `||`), down to a reference,
  /// a comparison or a `!`. Empty when it is true.
  List<Expression> falseParts(Map<String, Object?> scope) =>
      Expression.isTruthy(evaluate(scope)) ? const [] : _whyFalse(scope);

  /// [falseParts] of an expression that is false.
  List<Expression> _whyFalse(Map<String, Object?> scope) => [this];

  @override
  String toString() => source;

  /// Whether [value] counts as true.
  static bool isTruthy(Object? value) =>
      value != null && value != false && value != 0 && value != '';
}

final class _Literal extends Expression {
  const new(this.value);

  final Object? value;

  @override
  Object? evaluate(Map<String, Object?> scope) => value;

  @override
  Set<String> get variables => const {};

  @override
  Set<String> get paths => const {};

  @override
  String get source => value is String
      ? "'${(value! as String).replaceAll("'", "''")}'"
      : '$value';
}

final class _Reference extends Expression {
  const new(this.name);

  final String name;

  @override
  Object? evaluate(Map<String, Object?> scope) => scope[name];

  @override
  Set<String> get variables => {name};

  @override
  Set<String> get paths => {name};

  @override
  String get _chain => name;

  @override
  String get source => name;
}

final class _Member extends Expression {
  const new(this.target, this.key);

  final Expression target;
  final Expression key;

  @override
  Object? evaluate(Map<String, Object?> scope) {
    final holder = target.evaluate(scope);
    final index = key.evaluate(scope);
    if (holder is Map<String, Object?>) return holder['$index'];
    if (holder is List<Object?> && index is int) {
      return index >= 0 && index < holder.length ? holder[index] : null;
    }
    return null;
  }

  @override
  Set<String> get variables => {...target.variables, ...key.variables};

  @override
  Set<String> get paths => switch (_chain) {
    final chain? => {chain},
    null => {...target.paths, ...key.paths},
  };

  @override
  String? get _chain => switch ((target._chain, key)) {
    (final chain?, _Literal(:final String value)) => '$chain.$value',
    _ => null,
  };

  @override
  String get source => switch (key) {
    _Literal(:final String value) when _isName(value) =>
      '${target.source}.$value',
    _ => '${target.source}[${key.source}]',
  };

  static bool _isName(String text) =>
      text.isNotEmpty &&
      _nameStart.hasMatch(text[0]) &&
      text.split('').every(_namePart.hasMatch);
}

final class _Not extends Expression {
  const new(this.operand);

  final Expression operand;

  @override
  Object? evaluate(Map<String, Object?> scope) =>
      !Expression.isTruthy(operand.evaluate(scope));

  @override
  Set<String> get variables => operand.variables;

  @override
  Set<String> get paths => operand.paths;

  @override
  String get source => '!${operand.source}';
}

final class _Equals extends Expression {
  const new(this.left, this.right, {required this.negated});

  final Expression left;
  final Expression right;
  final bool negated;

  @override
  Object? evaluate(Map<String, Object?> scope) {
    final same = const DeepCollectionEquality().equals(
      left.evaluate(scope),
      right.evaluate(scope),
    );
    return same != negated;
  }

  @override
  Set<String> get variables => {...left.variables, ...right.variables};

  @override
  Set<String> get paths => {...left.paths, ...right.paths};

  @override
  String get source =>
      '${left.source} ${negated ? '!=' : '=='} ${right.source}';
}

final class _Logical extends Expression {
  const new(this.left, this.right, {required this.isAnd});

  final Expression left;
  final Expression right;
  final bool isAnd;

  @override
  Object? evaluate(Map<String, Object?> scope) {
    final first = left.evaluate(scope);
    return Expression.isTruthy(first) == isAnd ? right.evaluate(scope) : first;
  }

  @override
  List<Expression> _whyFalse(Map<String, Object?> scope) {
    final leftFalse = left.falseParts(scope);
    if (isAnd) return leftFalse.isNotEmpty ? leftFalse : right._whyFalse(scope);
    return [...leftFalse, ...right.falseParts(scope)];
  }

  @override
  Set<String> get variables => {...left.variables, ...right.variables};

  @override
  Set<String> get paths => {...left.paths, ...right.paths};

  @override
  String get source =>
      '(${left.source} ${isAnd ? '&&' : '||'} ${right.source})';
}

enum _Kind {
  name,
  number,
  string,
  equals,
  notEquals,
  and,
  or,
  not,
  open,
  close,
  dot,
  openIndex,
  closeIndex,
  end,
}

class _Token {
  const new(this.kind, this.offset, [this.value]);

  final _Kind kind;
  final int offset;
  final Object? value;
}

final _nameStart = RegExp('[A-Za-z_]');
final _namePart = RegExp('[A-Za-z0-9_]');
final _digit = RegExp('[0-9]');

List<_Token> _tokenize(String source) {
  final tokens = <_Token>[];
  var i = 0;
  while (i < source.length) {
    final char = source[i];
    final next = i + 1 < source.length ? source[i + 1] : '';
    if (char == ' ' || char == '\t' || char == '\n' || char == '\r') {
      i++;
    } else if (char == '=' && next == '=') {
      tokens.add(_Token(_Kind.equals, i));
      i += 2;
    } else if (char == '!' && next == '=') {
      tokens.add(_Token(_Kind.notEquals, i));
      i += 2;
    } else if (char == '&' && next == '&') {
      tokens.add(_Token(_Kind.and, i));
      i += 2;
    } else if (char == '|' && next == '|') {
      tokens.add(_Token(_Kind.or, i));
      i += 2;
    } else if (char == '!') {
      tokens.add(_Token(_Kind.not, i++));
    } else if (char == '(') {
      tokens.add(_Token(_Kind.open, i++));
    } else if (char == ')') {
      tokens.add(_Token(_Kind.close, i++));
    } else if (char == '.') {
      tokens.add(_Token(_Kind.dot, i++));
    } else if (char == '[') {
      tokens.add(_Token(_Kind.openIndex, i++));
    } else if (char == ']') {
      tokens.add(_Token(_Kind.closeIndex, i++));
    } else if (char == "'" || char == '"') {
      final start = i++;
      final text = StringBuffer();
      var closed = false;
      while (i < source.length) {
        if (source[i] != char) {
          text.write(source[i++]);
        } else if (i + 1 < source.length && source[i + 1] == char) {
          text.write(char);
          i += 2;
        } else {
          closed = true;
          i++;
          break;
        }
      }
      if (!closed) {
        throw ExpressionException('The string is not closed.', start);
      }
      tokens.add(_Token(_Kind.string, start, '$text'));
    } else if (_digit.hasMatch(char)) {
      final start = i;
      while (i < source.length && _digit.hasMatch(source[i])) {
        i++;
      }
      tokens.add(
        _Token(_Kind.number, start, int.parse(source.substring(start, i))),
      );
    } else if (_nameStart.hasMatch(char)) {
      final start = i;
      while (i < source.length && _namePart.hasMatch(source[i])) {
        i++;
      }
      tokens.add(_Token(_Kind.name, start, source.substring(start, i)));
    } else {
      throw ExpressionException(
        char == '=' || char == '&' || char == '|'
            ? 'Unexpected "$char"; did you mean "$char$char"?'
            : 'Unexpected "$char".',
        i,
      );
    }
  }
  tokens.add(_Token(_Kind.end, source.length));
  return tokens;
}

class _Parser {
  new(String source) : _tokens = _tokenize(source);

  final List<_Token> _tokens;
  var _position = 0;

  _Token get _current => _tokens[_position];

  Expression parse() {
    if (_current.kind == _Kind.end) {
      throw ExpressionException('The expression is empty.', _current.offset);
    }
    final expression = _or();
    if (_current.kind != _Kind.end) {
      throw ExpressionException(
        'Unexpected ${_describe(_current)}.',
        _current.offset,
      );
    }
    return expression;
  }

  Expression _or() {
    var left = _and();
    while (_current.kind == _Kind.or) {
      _position++;
      left = _Logical(left, _and(), isAnd: false);
    }
    return left;
  }

  Expression _and() {
    var left = _equality();
    while (_current.kind == _Kind.and) {
      _position++;
      left = _Logical(left, _equality(), isAnd: true);
    }
    return left;
  }

  Expression _equality() {
    var left = _unary();
    while (_current.kind == _Kind.equals || _current.kind == _Kind.notEquals) {
      final negated = _current.kind == _Kind.notEquals;
      _position++;
      left = _Equals(left, _unary(), negated: negated);
    }
    return left;
  }

  Expression _unary() {
    if (_current.kind == _Kind.not) {
      _position++;
      return _Not(_unary());
    }
    return _postfix();
  }

  Expression _postfix() {
    var target = _primary();
    while (true) {
      if (_current.kind == _Kind.dot) {
        _position++;
        final name = _current;
        if (name.kind != _Kind.name) {
          throw ExpressionException(
            'Expected a name after ".", not ${_describe(name)}.',
            name.offset,
          );
        }
        _position++;
        target = _Member(target, _Literal(name.value));
      } else if (_current.kind == _Kind.openIndex) {
        _position++;
        final key = _or();
        if (_current.kind != _Kind.closeIndex) {
          throw ExpressionException(
            'Expected "]", not ${_describe(_current)}.',
            _current.offset,
          );
        }
        _position++;
        target = _Member(target, key);
      } else {
        return target;
      }
    }
  }

  Expression _primary() {
    final token = _current;
    switch (token.kind) {
      case _Kind.string || _Kind.number:
        _position++;
        return _Literal(token.value);
      case _Kind.name:
        _position++;
        final name = token.value! as String;
        return switch (name) {
          'true' => const _Literal(true),
          'false' => const _Literal(false),
          'null' => const _Literal(null),
          _ => _Reference(name),
        };
      case _Kind.open:
        _position++;
        final inner = _or();
        if (_current.kind != _Kind.close) {
          throw ExpressionException(
            'Expected ")", not ${_describe(_current)}.',
            _current.offset,
          );
        }
        _position++;
        return inner;
      case _:
        throw ExpressionException(
          'Expected a value, not ${_describe(token)}.',
          token.offset,
        );
    }
  }

  static String _describe(_Token token) => switch (token.kind) {
    _Kind.end => 'the end of the expression',
    _Kind.name => 'the name "${token.value}"',
    _Kind.number => 'the number ${token.value}',
    _Kind.string => 'a string',
    _Kind.equals => '"=="',
    _Kind.notEquals => '"!="',
    _Kind.and => '"&&"',
    _Kind.or => '"||"',
    _Kind.not => '"!"',
    _Kind.open => '"("',
    _Kind.close => '")"',
    _Kind.dot => '"."',
    _Kind.openIndex => '"["',
    _Kind.closeIndex => '"]"',
  };
}

/// A string of a workflow that may hold `${{ expression }}` placeholders.
///
/// A string that is one placeholder and nothing else keeps the type of its
/// value (a list stays a list); a string with text around its placeholders
/// becomes text, where `null` is empty and lists and maps are JSON.
class Template {
  const new _(this._parts);

  /// Reads [source].
  ///
  /// Throws an [ExpressionException] for a placeholder that is not closed or
  /// whose expression is not valid; its offset is in [source].
  factory parse(String source) {
    final parts = <Object>[];
    var i = 0;
    while (i < source.length) {
      final open = source.indexOf(r'${{', i);
      if (open < 0) {
        parts.add(source.substring(i));
        break;
      }
      if (open > i) parts.add(source.substring(i, open));
      final close = source.indexOf('}}', open + 3);
      if (close < 0) {
        throw ExpressionException(r'"${{" is not closed by "}}".', open);
      }
      final inner = source.substring(open + 3, close);
      try {
        parts.add(Expression.parse(inner));
      } on ExpressionException catch (error) {
        throw ExpressionException(error.message, open + 3 + error.offset);
      }
      i = close + 2;
    }
    return ._(parts);
  }

  final List<Object> _parts;

  /// The expressions in the string.
  Iterable<Expression> get expressions => _parts.whereType<Expression>();

  /// Whether the string holds any placeholder.
  bool get hasPlaceholders => _parts.any((part) => part is Expression);

  /// Whether the string is one placeholder and nothing else, so that its value
  /// keeps its type.
  bool get isSinglePlaceholder =>
      _parts.length == 1 && _parts.single is Expression;

  /// The value of the string, reading variables from [scope].
  Object? evaluate(Map<String, Object?> scope) {
    if (isSinglePlaceholder) {
      return (_parts.single as Expression).evaluate(scope);
    }
    final text = StringBuffer();
    for (final part in _parts) {
      if (part is Expression) {
        text.write(_text(part.evaluate(scope)));
      } else {
        text.write(part);
      }
    }
    return '$text';
  }

  static String _text(Object? value) => switch (value) {
    null => '',
    String() || num() || bool() => '$value',
    _ => jsonEncode(value),
  };
}

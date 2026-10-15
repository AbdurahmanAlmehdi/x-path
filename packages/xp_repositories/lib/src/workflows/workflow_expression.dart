import 'dart:convert';

/// The value of the workflow expression [source], reading variables from
/// [scope].
///
/// The same small language the engine reads (`platform == 'android' &&
/// !flavor.shorebird`): `null`, `true`, `false`, numbers and strings; names
/// and `a.b` / `a['b']` / `a[0]` reads, where reading what is not there gives
/// `null`; `==`, `!=`, `!`, and `&&` / `||`, which give one of their
/// operands. The app only reads workflows to preview a dispatch: the engine
/// stays the judge of what runs.
///
/// Throws a [FormatException] for text that is not an expression.
Object? evaluateExpression(String source, Map<String, Object?> scope) =>
    _Parser(source, scope).parse();

/// Whether [value] counts as true: everything but `null`, `false`, `0` and
/// `''`.
bool isTruthy(Object? value) =>
    value != null && value != false && value != 0 && value != '';

/// The value of a workflow string that may hold `${{ expression }}`
/// placeholders. A string that is one placeholder and nothing else keeps the
/// type of its value (a list stays a list); otherwise the result is text,
/// where `null` is empty and lists and maps are JSON.
///
/// Throws a [FormatException] for a placeholder that is not closed or not an
/// expression.
Object? renderTemplate(String source, Map<String, Object?> scope) {
  final parts = <Object?>[];
  var i = 0;
  while (i < source.length) {
    final open = source.indexOf(r'${{', i);
    if (open < 0) {
      parts.add(source.substring(i));
      break;
    }
    if (open > i) parts.add(source.substring(i, open));
    final close = source.indexOf('}}', open + 3);
    if (close < 0) throw FormatException(r'"${{" is not closed.', source);
    parts.add(
      _Value(evaluateExpression(source.substring(open + 3, close), scope)),
    );
    i = close + 2;
  }
  if (parts case [final _Value only]) return only.value;
  return parts.map((part) => part is _Value ? _text(part.value) : part).join();
}

String _text(Object? value) => switch (value) {
  null => '',
  String() || num() || bool() => '$value',
  _ => jsonEncode(value),
};

class _Value {
  const new(this.value);

  final Object? value;
}

enum _Kind {
  name,
  string,
  number,
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
  const new(this.kind, [this.value]);

  final _Kind kind;
  final Object? value;
}

final _namePart = RegExp('[A-Za-z0-9_-]');
final _nameStart = RegExp('[A-Za-z_]');
final _digit = RegExp('[0-9]');

List<_Token> _tokenize(String source) {
  final tokens = <_Token>[];
  var i = 0;
  const pairs = {
    '==': _Kind.equals,
    '!=': _Kind.notEquals,
    '&&': _Kind.and,
    '||': _Kind.or,
  };
  const singles = {
    '!': _Kind.not,
    '(': _Kind.open,
    ')': _Kind.close,
    '.': _Kind.dot,
    '[': _Kind.openIndex,
    ']': _Kind.closeIndex,
  };
  while (i < source.length) {
    final char = source[i];
    final pair = i + 1 < source.length ? source.substring(i, i + 2) : '';
    if (char.trim().isEmpty) {
      i++;
    } else if (pairs[pair] case final kind?) {
      tokens.add(_Token(kind));
      i += 2;
    } else if (singles[char] case final kind?) {
      tokens.add(_Token(kind));
      i++;
    } else if (char == "'" || char == '"') {
      final text = StringBuffer();
      var closed = false;
      i++;
      while (i < source.length) {
        if (source[i] == char) {
          if (i + 1 < source.length && source[i + 1] == char) {
            text.write(char);
            i += 2;
            continue;
          }
          closed = true;
          i++;
          break;
        }
        text.write(source[i]);
        i++;
      }
      if (!closed) throw FormatException('The string is not closed.', source);
      tokens.add(_Token(_Kind.string, '$text'));
    } else if (_digit.hasMatch(char)) {
      final start = i;
      while (i < source.length && _digit.hasMatch(source[i])) {
        i++;
      }
      tokens.add(_Token(_Kind.number, int.parse(source.substring(start, i))));
    } else if (_nameStart.hasMatch(char)) {
      final start = i;
      while (i < source.length && _namePart.hasMatch(source[i])) {
        i++;
      }
      tokens.add(_Token(_Kind.name, source.substring(start, i)));
    } else {
      throw FormatException('Unexpected "$char".', source, i);
    }
  }
  return tokens..add(const _Token(_Kind.end));
}

/// Parses and evaluates at once: the language has no side effects, so both
/// operands of `&&` and `||` can be read before one is picked.
class _Parser {
  new(this._source, this._scope) : _tokens = _tokenize(_source);

  final String _source;
  final Map<String, Object?> _scope;
  final List<_Token> _tokens;
  var _position = 0;

  _Token get _current => _tokens[_position];

  Never _fail(String message) => throw FormatException(message, _source);

  void _expect(_Kind kind) {
    if (_current.kind != kind) _fail('Unexpected ${_current.kind.name}.');
    _position++;
  }

  Object? parse() {
    final value = _or();
    _expect(_Kind.end);
    return value;
  }

  Object? _or() {
    var left = _and();
    while (_current.kind == _Kind.or) {
      _position++;
      final right = _and();
      left = isTruthy(left) ? left : right;
    }
    return left;
  }

  Object? _and() {
    var left = _equality();
    while (_current.kind == _Kind.and) {
      _position++;
      final right = _equality();
      left = isTruthy(left) ? right : left;
    }
    return left;
  }

  Object? _equality() {
    var left = _unary();
    while (_current.kind == _Kind.equals || _current.kind == _Kind.notEquals) {
      final negated = _current.kind == _Kind.notEquals;
      _position++;
      final equal = left == _unary();
      left = negated ? !equal : equal;
    }
    return left;
  }

  Object? _unary() {
    if (_current.kind == _Kind.not) {
      _position++;
      return !isTruthy(_unary());
    }
    return _postfix();
  }

  Object? _postfix() {
    var target = _primary();
    while (true) {
      if (_current.kind == _Kind.dot) {
        _position++;
        final name = _current;
        _expect(_Kind.name);
        target = _member(target, name.value);
      } else if (_current.kind == _Kind.openIndex) {
        _position++;
        final key = _or();
        _expect(_Kind.closeIndex);
        target = _member(target, key);
      } else {
        return target;
      }
    }
  }

  static Object? _member(Object? target, Object? key) => switch (target) {
    final Map<Object?, Object?> map => map[key],
    final List<Object?> list when key is int && key >= 0 && key < list.length =>
      list[key],
    _ => null,
  };

  Object? _primary() {
    final token = _current;
    _position++;
    switch (token.kind) {
      case _Kind.string || _Kind.number:
        return token.value;
      case _Kind.name:
        return switch (token.value) {
          'true' => true,
          'false' => false,
          'null' => null,
          final Object? name => _scope[name],
        };
      case _Kind.open:
        final inner = _or();
        _expect(_Kind.close);
        return inner;
      case _:
        _fail('Expected a value, not ${token.kind.name}.');
    }
  }
}

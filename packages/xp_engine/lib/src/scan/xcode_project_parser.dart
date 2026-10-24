import 'package:equatable/equatable.dart';

/// One build configuration, for example `Release-dev`, with its settings.
class XcodeBuildConfiguration extends Equatable {
  /// Creates a configuration.
  const new(this.name, this.settings);

  /// The configuration name.
  final String name;

  /// The build settings that are plain strings. Lists are left out.
  final Map<String, String> settings;

  @override
  List<Object?> get props => [name, settings];
}

/// A native target with its build configurations.
class XcodeTarget extends Equatable {
  /// Creates a target.
  const new({
    required this.name,
    required this.productType,
    required this.configurations,
  });

  /// The target name, for example `Runner`.
  final String name;

  /// The product type, for example `com.apple.product-type.application`.
  final String productType;

  /// The configurations of the target.
  final List<XcodeBuildConfiguration> configurations;

  /// Whether the target builds an app, as opposed to a test bundle or an app
  /// extension.
  bool get isApplication => productType == 'com.apple.product-type.application';

  /// Whether the target builds an app extension: a widget, a share or
  /// notification service extension, an iMessage or watch extension.
  bool get isAppExtension => productType.contains('extension');

  @override
  List<Object?> get props => [name, productType, configurations];
}

/// The parts of a `project.pbxproj` the scanner needs.
class XcodeProject extends Equatable {
  /// Creates a project.
  const new({
    required this.targets,
    required this.projectConfigurations,
    required this.usesSwiftPackages,
  });

  /// The native targets.
  final List<XcodeTarget> targets;

  /// The configurations of the project itself, which targets inherit from.
  final List<XcodeBuildConfiguration> projectConfigurations;

  /// Whether the project references Swift packages.
  final bool usesSwiftPackages;

  /// The target that builds the Flutter app: `Runner` if it is an application,
  /// else the first application target.
  XcodeTarget? get appTarget {
    final apps = targets.where((target) => target.isApplication).toList();
    for (final target in apps) {
      if (target.name == 'Runner') return target;
    }
    return apps.isEmpty ? null : apps.first;
  }

  /// The settings of [target] for the configuration [name], falling back to
  /// the project's settings for what the target leaves unset.
  Map<String, String>? settingsOf(XcodeTarget target, String name) {
    final own = _named(target.configurations, name);
    final inherited = _named(projectConfigurations, name);
    if (own == null && inherited == null) return null;
    return {...?inherited?.settings, ...?own?.settings};
  }

  static XcodeBuildConfiguration? _named(
    List<XcodeBuildConfiguration> configurations,
    String name,
  ) {
    for (final configuration in configurations) {
      if (configuration.name == name) return configuration;
    }
    return null;
  }

  @override
  List<Object?> get props => [
    targets,
    projectConfigurations,
    usesSwiftPackages,
  ];
}

/// Reads [pbxproj], the text of a `project.pbxproj`, or returns `null` if it
/// is not one.
XcodeProject? parseXcodeProject(String pbxproj) {
  final Object? root;
  try {
    root = _PlistReader(pbxproj).read();
  } on FormatException {
    return null;
  }
  if (root is! Map<String, Object?>) return null;
  final objects = root['objects'];
  if (objects is! Map<String, Object?>) return null;
  final project = objects[root['rootObject']];
  if (project is! Map<String, Object?>) return null;

  Map<String, Object?> object(Object? id) {
    final found = objects[id];
    return found is Map<String, Object?> ? found : const {};
  }

  List<XcodeBuildConfiguration> configurations(Object? listId) {
    final ids = object(listId)['buildConfigurations'];
    return [
      if (ids is List<Object?>)
        for (final id in ids) _configuration(object(id)),
    ];
  }

  final targetIds = project['targets'];
  return XcodeProject(
    targets: [
      if (targetIds is List<Object?>)
        for (final id in targetIds)
          if (object(id)['isa'] == 'PBXNativeTarget')
            XcodeTarget(
              name: '${object(id)['name']}',
              productType: '${object(id)['productType']}',
              configurations: configurations(
                object(id)['buildConfigurationList'],
              ),
            ),
    ],
    projectConfigurations: configurations(project['buildConfigurationList']),
    usesSwiftPackages: objects.values.any(
      (value) =>
          value is Map<String, Object?> &&
          (value['isa'] == 'XCLocalSwiftPackageReference' ||
              value['isa'] == 'XCRemoteSwiftPackageReference' ||
              value['isa'] == 'XCSwiftPackageProductDependency'),
    ),
  );
}

XcodeBuildConfiguration _configuration(Map<String, Object?> object) {
  final settings = object['buildSettings'];
  return XcodeBuildConfiguration('${object['name']}', {
    if (settings is Map<String, Object?>)
      for (final entry in settings.entries)
        if (entry.value case final String value) entry.key: value,
  });
}

/// A reader for the old-style property list that `project.pbxproj` is: dicts
/// `{ k = v; }`, arrays `( v, )`, and quoted or bare strings, with `/* */` and
/// `//` comments.
class _PlistReader {
  new(this._text);

  final String _text;
  var _pos = 0;

  Object? read() {
    final value = _value();
    _skipSpace();
    if (_pos != _text.length) throw const FormatException('trailing text');
    return value;
  }

  Object? _value() {
    _skipSpace();
    if (_pos >= _text.length) throw const FormatException('unexpected end');
    return switch (_text[_pos]) {
      '{' => _dict(),
      '(' => _array(),
      '"' => _quoted(),
      _ => _bare(),
    };
  }

  Map<String, Object?> _dict() {
    _pos++;
    final result = <String, Object?>{};
    while (true) {
      _skipSpace();
      if (_peek('}')) {
        _pos++;
        return result;
      }
      final key = _string();
      _skipSpace();
      _expect('=');
      result[key] = _value();
      _skipSpace();
      _expect(';');
    }
  }

  List<Object?> _array() {
    _pos++;
    final result = <Object?>[];
    while (true) {
      _skipSpace();
      if (_peek(')')) {
        _pos++;
        return result;
      }
      result.add(_value());
      _skipSpace();
      if (_peek(',')) _pos++;
    }
  }

  String _string() {
    _skipSpace();
    if (_pos >= _text.length) throw const FormatException('unexpected end');
    return _text[_pos] == '"' ? _quoted() : _bare();
  }

  String _quoted() {
    _pos++;
    final out = StringBuffer();
    while (_pos < _text.length) {
      final char = _text[_pos++];
      if (char == '"') return out.toString();
      if (char == r'\' && _pos < _text.length) {
        final escaped = _text[_pos++];
        out.write(switch (escaped) {
          'n' => '\n',
          't' => '\t',
          _ => escaped,
        });
      } else {
        out.write(char);
      }
    }
    throw const FormatException('unterminated string');
  }

  static final _bareChar = RegExp(r'[^\s;,=(){}"]');

  String _bare() {
    final start = _pos;
    while (_pos < _text.length && _bareChar.hasMatch(_text[_pos])) {
      _pos++;
    }
    if (_pos == start) throw FormatException('unexpected ${_text[_pos]}');
    return _text.substring(start, _pos);
  }

  bool _peek(String char) => _pos < _text.length && _text[_pos] == char;

  void _expect(String char) {
    if (!_peek(char)) throw FormatException('expected $char');
    _pos++;
  }

  void _skipSpace() {
    while (_pos < _text.length) {
      final char = _text[_pos];
      if (char.trim().isEmpty) {
        _pos++;
      } else if (_text.startsWith('/*', _pos)) {
        final end = _text.indexOf('*/', _pos + 2);
        _pos = end < 0 ? _text.length : end + 2;
      } else if (_text.startsWith('//', _pos)) {
        final end = _text.indexOf('\n', _pos);
        _pos = end < 0 ? _text.length : end + 1;
      } else {
        return;
      }
    }
  }
}

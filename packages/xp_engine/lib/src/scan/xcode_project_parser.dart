import 'package:equatable/equatable.dart';

/// One build configuration, for example `Release-dev`, with its settings.
class XcodeBuildConfiguration extends Equatable {
  /// Creates a configuration.
  const new(this.name, this.settings, {this.baseConfiguration});

  /// The configuration name.
  final String name;

  /// The build settings that are plain strings. Lists are left out.
  final Map<String, String> settings;

  /// The `.xcconfig` it is based on (`baseConfigurationReference`), relative
  /// to the folder of the `.xcodeproj`, for example
  /// `Flutter/devRelease.xcconfig`.
  final String? baseConfiguration;

  @override
  List<Object?> get props => [name, settings, baseConfiguration];
}

/// A Run Script build phase of a target.
class XcodeScriptPhase extends Equatable {
  /// Creates a phase.
  const new(this.name, this.script);

  /// The phase name, for example `Thin Binary`; `Run Script` when unnamed.
  final String name;

  /// The shell script.
  final String script;

  /// Whether it is one of Flutter's own phases, every line of which runs
  /// `xcode_backend.sh` (`build`, `embed_and_thin`).
  bool get isFlutter {
    final lines = [
      for (final line in script.split('\n'))
        if (line.trim() case final line
            when line.isNotEmpty && !line.startsWith('#'))
          line,
    ];
    return lines.isNotEmpty &&
        lines.every((line) => line.contains('xcode_backend.sh'));
  }

  /// Whether CocoaPods added it (`[CP] Embed Pods Frameworks`, ...).
  bool get isCocoaPods => name.startsWith('[CP');

  @override
  List<Object?> get props => [name, script];
}

/// A native target with its build configurations.
class XcodeTarget extends Equatable {
  /// Creates a target.
  const new({
    required this.name,
    required this.productType,
    required this.configurations,
    this.scriptPhases = const [],
    this.resources = const [],
  });

  /// The target name, for example `Runner`.
  final String name;

  /// The product type, for example `com.apple.product-type.application`.
  final String productType;

  /// The configurations of the target.
  final List<XcodeBuildConfiguration> configurations;

  /// Its Run Script build phases, in build order.
  final List<XcodeScriptPhase> scriptPhases;

  /// What its Copy Bundle Resources phase copies, relative to the folder of
  /// the `.xcodeproj`, for example `Runner/Assets.xcassets`.
  final List<String> resources;

  /// Whether the target builds an app, as opposed to a test bundle or an app
  /// extension.
  bool get isApplication => productType == 'com.apple.product-type.application';

  /// Whether the target builds an app extension: a widget, a share or
  /// notification service extension, an iMessage or watch extension.
  bool get isAppExtension => productType.contains('extension');

  @override
  List<Object?> get props => [
    name,
    productType,
    configurations,
    scriptPhases,
    resources,
  ];
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

  /// The configurations of [target] or the project that
  /// `flutter build --flavor` may build [flavor] with (flutter_tools
  /// `xcodeproj.dart`): `Release-<flavor>` when there is one, else those
  /// whose name is that ignoring case; `Release` without a flavor. One is the
  /// configuration it builds; none or several fail the build.
  List<String> releaseConfigurationsFor(XcodeTarget target, String? flavor) {
    final expected = flavor == null ? 'Release' : 'Release-$flavor';
    final names = {
      for (final configuration in [
        ...target.configurations,
        ...projectConfigurations,
      ])
        configuration.name,
    };
    if (names.contains(expected)) return [expected];
    return [
      for (final name in names)
        if (name.toLowerCase() == expected.toLowerCase()) name,
    ];
  }

  /// The `.xcconfig` files the configuration [name] of [target] is based on:
  /// the project's, then the target's.
  List<String> baseConfigurationsOf(XcodeTarget target, String name) => [
    ?_named(projectConfigurations, name)?.baseConfiguration,
    ?_named(target.configurations, name)?.baseConfiguration,
  ];

  /// The settings of [target] for the configuration [name] as Xcode layers
  /// them, each layer over the one before: the project's `.xcconfig`, the
  /// project, the target's `.xcconfig`, the target. [xcconfigs] holds the
  /// settings of each file of [baseConfigurationsOf].
  Map<String, String> layeredSettingsOf(
    XcodeTarget target,
    String name,
    Map<String, Map<String, String>> xcconfigs,
  ) {
    final project = _named(projectConfigurations, name);
    final own = _named(target.configurations, name);
    return {
      ...?xcconfigs[project?.baseConfiguration],
      ...?project?.settings,
      ...?xcconfigs[own?.baseConfiguration],
      ...?own?.settings,
    };
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

  List<Object?> list(Object? value) =>
      value is List<Object?> ? value : const [];

  // Groups and files are found by path through the groups that hold them.
  final parents = <Object?, Object?>{
    for (final entry in objects.entries)
      if (entry.value case {'children': final List<Object?> children})
        for (final child in children) child: entry.key,
  };
  String? pathOf(Object? id, [int depth = 0]) {
    final item = object(id);
    final own = item['path'] ?? (item['isa'] == 'PBXGroup' ? '' : item['name']);
    if (own is! String || depth > 64) return null;
    if (item['sourceTree'] == 'SOURCE_ROOT') return own;
    if (item['sourceTree'] != '<group>') return null;
    if (!parents.containsKey(id)) return own;
    final parent = pathOf(parents[id], depth + 1);
    if (parent == null) return null;
    return [parent, own].where((part) => part.isNotEmpty).join('/');
  }

  List<XcodeBuildConfiguration> configurations(Object? listId) => [
    for (final id in list(object(listId)['buildConfigurations']))
      _configuration(
        object(id),
        baseConfiguration: pathOf(object(id)['baseConfigurationReference']),
      ),
  ];

  XcodeTarget target(Object? id) {
    final target = object(id);
    final phases = list(target['buildPhases']).map(object);
    return XcodeTarget(
      name: '${target['name']}',
      productType: '${target['productType']}',
      configurations: configurations(target['buildConfigurationList']),
      scriptPhases: [
        for (final phase in phases)
          if (phase['isa'] == 'PBXShellScriptBuildPhase')
            XcodeScriptPhase(
              switch (phase['name']) {
                final String name => name,
                _ => 'Run Script',
              },
              switch (phase['shellScript']) {
                final String script => script,
                _ => '',
              },
            ),
      ],
      resources: [
        for (final phase in phases)
          if (phase['isa'] == 'PBXResourcesBuildPhase')
            for (final file in list(phase['files']))
              ?pathOf(object(file)['fileRef']),
      ],
    );
  }

  return XcodeProject(
    targets: [
      for (final id in list(project['targets']))
        if (object(id)['isa'] == 'PBXNativeTarget') target(id),
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

XcodeBuildConfiguration _configuration(
  Map<String, Object?> object, {
  String? baseConfiguration,
}) {
  final settings = object['buildSettings'];
  return XcodeBuildConfiguration('${object['name']}', {
    if (settings is Map<String, Object?>)
      for (final entry in settings.entries)
        if (entry.value case final String value) entry.key: value,
  }, baseConfiguration: baseConfiguration);
}

/// The parts of an `.xcconfig` file the scanner needs.
class Xcconfig extends Equatable {
  /// Creates one.
  const new({this.includes = const [], this.settings = const {}});

  /// The files its `#include` and `#include?` lines name, relative to it.
  final List<String> includes;

  /// Its settings. Conditional ones (`KEY[sdk=...]`) are left out.
  final Map<String, String> settings;

  @override
  List<Object?> get props => [includes, settings];
}

final _include = RegExp(r'^#include\??\s+"([^"]+)"');
final _setting = RegExp(r'^([A-Za-z_][A-Za-z0-9_]*)\s*=(.*)$');

/// Reads [text], the content of an `.xcconfig`. Its includes come before its
/// own settings, which win over theirs, as they do when the includes are at
/// the top.
Xcconfig parseXcconfig(String text) {
  final includes = <String>[];
  final settings = <String, String>{};
  for (final raw in text.split('\n')) {
    final line = raw.split('//').first.trim();
    if (_include.firstMatch(line) case final match?) {
      includes.add(match[1]!);
    } else if (_setting.firstMatch(line) case final match?) {
      final value = match[2]!.trim();
      settings[match[1]!] = value.endsWith(';')
          ? value.substring(0, value.length - 1).trim()
          : value;
    }
  }
  return Xcconfig(includes: includes, settings: settings);
}

final _reference = RegExp(r'\$[({]([A-Za-z_][A-Za-z0-9_]*)[)}]');

/// [value] with the `$(NAME)` and `${NAME}` references to [settings]
/// replaced, as Xcode expands them; `$(inherited)` is empty. A reference to
/// a setting that is not there is kept.
String expandBuildSetting(String value, Map<String, String> settings) {
  var expanded = value;
  for (var round = 0; round < 8 && expanded.contains(r'$'); round++) {
    expanded = expanded.replaceAllMapped(
      _reference,
      (match) =>
          match[1] == 'inherited' ? '' : settings[match[1]!] ?? match[0]!,
    );
  }
  return expanded;
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

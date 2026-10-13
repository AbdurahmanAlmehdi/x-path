import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xp_tool/src/layer_rules.dart';
import 'package:yaml/yaml.dart';

/// A place where the dependency direction is broken.
class LayerViolation {
  /// Creates a violation found at [location].
  const new({required this.location, required this.message});

  /// A file path (with a line number for source files) or a `pubspec.yaml`.
  final String location;

  /// What is wrong.
  final String message;

  @override
  String toString() => '$location: $message';
}

/// The source folders scanned for `import` and `export` directives.
const _sourceFolders = ['lib', 'test', 'bin', 'integration_test'];

final _directive = RegExp(
  r'^[ \t]*(?:import|export)\s+([^;]*);',
  multiLine: true,
);
final _stringLiteral = RegExp('''['"]([^'"]+)['"]''');

/// Checks every package of the pub workspace at [root] against [rules].
///
/// Returns the violations, sorted by location. An empty list means the
/// dependency direction holds.
List<LayerViolation> checkLayers(
  Directory root, {
  Map<String, LayerRule> rules = layerRules,
}) {
  final violations = <LayerViolation>[];
  final members = _readMembers(root, violations);
  final names = members.map((m) => m.name).toSet();

  for (final member in members) {
    final rule = rules[member.name];
    if (rule == null) {
      violations.add(
        .new(
          location: p.relative(
            p.join(member.path, 'pubspec.yaml'),
            from: root.path,
          ),
          message:
              'no layer rule for ${member.name}; add it to layerRules in '
              'tool/lib/src/layer_rules.dart',
        ),
      );
      continue;
    }
    _MemberChecker(root.path, member, rule, names, violations)
      ..checkPubspec()
      ..checkSources();
  }

  return violations..sort((a, b) => a.location.compareTo(b.location));
}

/// Runs the layer check for the workspace at [root] and returns an exit code.
///
/// Violations go to [err], the summary to [out].
int runCheckLayers({
  required Directory root,
  required StringSink out,
  required StringSink err,
  Map<String, LayerRule> rules = layerRules,
}) {
  final violations = checkLayers(root, rules: rules);
  if (violations.isEmpty) {
    out.writeln('Layer check passed.');
    return 0;
  }
  violations.forEach(err.writeln);
  err.writeln('Layer check failed: ${violations.length} violation(s).');
  return 1;
}

class _Member {
  const new({required this.name, required this.path, required this.yaml});

  final String name;
  final String path;
  final YamlMap yaml;
}

List<_Member> _readMembers(Directory root, List<LayerViolation> violations) {
  final rootPubspec = loadYaml(
    File(p.join(root.path, 'pubspec.yaml')).readAsStringSync(),
  ) as YamlMap;
  final members = <_Member>[];
  for (final entry in rootPubspec['workspace'] as YamlList) {
    final path = p.normalize(p.join(root.path, entry as String));
    final pubspec = File(p.join(path, 'pubspec.yaml'));
    if (!pubspec.existsSync()) {
      violations.add(
        .new(
          location: p.relative(pubspec.path, from: root.path),
          message: 'listed in the workspace but missing',
        ),
      );
      continue;
    }
    final yaml = loadYaml(pubspec.readAsStringSync()) as YamlMap;
    members.add(_Member(name: yaml['name'] as String, path: path, yaml: yaml));
  }
  return members;
}

class _MemberChecker {
  const new(
    this.rootPath,
    this.member,
    this.rule,
    this.workspaceNames,
    this.out,
  );

  final String rootPath;
  final _Member member;
  final LayerRule rule;
  final Set<String> workspaceNames;
  final List<LayerViolation> out;

  void checkPubspec() {
    final location = p.relative(
      p.join(member.path, 'pubspec.yaml'),
      from: rootPath,
    );
    for (final section in ['dependencies', 'dev_dependencies']) {
      final dependencies = member.yaml[section] as YamlMap?;
      for (final name in dependencies?.keys ?? const []) {
        _checkPackage(name as String, location);
      }
    }
  }

  void checkSources() {
    for (final folder in _sourceFolders) {
      final directory = Directory(p.join(member.path, folder));
      if (!directory.existsSync()) continue;
      directory
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .forEach(_checkFile);
    }
  }

  void _checkFile(File file) {
    final source = file.readAsStringSync();
    for (final directive in _directive.allMatches(source)) {
      final line = '\n'.allMatches(source.substring(0, directive.start)).length;
      final location = '${p.relative(file.path, from: rootPath)}:${line + 1}';
      for (final literal in _stringLiteral.allMatches(directive.group(1)!)) {
        _checkUri(literal.group(1)!, file, location);
      }
    }
  }

  void _checkUri(String uri, File file, String location) {
    if (uri.startsWith('package:')) {
      final path = uri.substring('package:'.length);
      _checkPackage(path.split('/').first, location);
    } else if (!uri.contains(':')) {
      final target = p.normalize(p.join(file.parent.path, uri));
      if (!p.isWithin(member.path, target)) {
        out.add(
          .new(
            location: location,
            message:
                '${member.name} must not import $uri: '
                'it points outside the package',
          ),
        );
      }
    }
  }

  void _checkPackage(String package, String location) {
    if (package == member.name) return;
    if (workspaceNames.contains(package)) {
      if (!rule.workspace.contains(package)) {
        out.add(
          .new(
            location: location,
            message:
                '${member.name} must not depend on $package '
                '(allowed workspace packages: ${_list(rule.workspace)})',
          ),
        );
      }
      return;
    }
    final external = rule.external;
    if (external != null && !external.contains(package)) {
      out.add(
        .new(
          location: location,
          message:
              '${member.name} must not depend on $package '
              '(allowed external packages: ${_list(external)})',
        ),
      );
    }
  }
}

String _list(Set<String> names) =>
    names.isEmpty ? 'none' : (names.toList()..sort()).join(', ');

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// The Linux workflow. Its `coverage` job must test every workspace package.
const gateWorkflow = '.github/workflows/gate.yaml';

/// The macOS workflow. Its `coverage` job must test every package that has
/// tests only macOS runs: a Flutter package, or a test tagged `macos` or
/// `golden`.
const macosWorkflow = '.github/workflows/macos.yaml';

/// A test file that only runs on macOS (see the tags in `dart_test.yaml`):
/// `@Tags([...])` or a test's `tags:` argument, at the start of a line.
final _macosOnlyTag = RegExp(
  r'''^[ \t]*(@Tags\(|tags:)[^;)]*['"](macos|golden)['"]''',
  multiLine: true,
);

/// Checks the `coverage` job matrices of [gateWorkflow] and [macosWorkflow]
/// against the pub workspace at [root].
///
/// Each matrix entry names a `package` and the `script` that runs it:
/// `test:coverage:<script>` of the root `pubspec.yaml`. The script must be the
/// one `melos run test:coverage` runs the package with, since a scoped
/// `melos run` of another script finds no package and exits 0: `strict` for
/// the packages in its scope, `flutter` for the other Flutter packages and
/// `floor` for the rest. A package without a `test/` directory has no entry.
///
/// Returns the problems, sorted. An empty list means no package goes
/// untested.
List<String> checkCiMatrix(Directory root) {
  final problems = <String>[];
  final rootPubspec = _load(p.join(root.path, 'pubspec.yaml'));
  final strictScope = _path(rootPubspec, [
    'melos',
    'scripts',
    'test:coverage:strict',
    'packageFilters',
    'scope',
  ]);
  final strict = {
    if (strictScope is YamlList)
      for (final name in strictScope) name as String,
  };

  final members = <String, _Member>{};
  for (final entry in rootPubspec['workspace'] as YamlList) {
    final path = p.join(root.path, entry as String);
    if (!File(p.join(path, 'pubspec.yaml')).existsSync()) {
      problems.add('$entry: listed in the workspace but has no pubspec.yaml');
      continue;
    }
    final pubspec = _load(p.join(path, 'pubspec.yaml'));
    members[pubspec['name'] as String] = _Member(path: path, pubspec: pubspec);
  }

  final scripts = <String, String>{};
  final macosOnly = <String>{};
  members.forEach((name, member) {
    final flutter = _needsFlutter(name, members);
    final tests = Directory(p.join(member.path, 'test'));
    if (strict.contains(name)) {
      scripts[name] = 'strict';
    } else if (tests.existsSync()) {
      scripts[name] = flutter ? 'flutter' : 'floor';
    }
    if (flutter || (tests.existsSync() && _hasMacosOnlyTests(tests))) {
      macosOnly.add(name);
    }
  });

  _checkWorkflow(root, gateWorkflow, scripts, scripts.keys, problems);
  _checkWorkflow(root, macosWorkflow, scripts, macosOnly, problems);
  return problems..sort();
}

/// Runs [checkCiMatrix] for the workspace at [root] and returns an exit code.
///
/// Problems go to [err], the summary to [out].
int runCheckCiMatrix({
  required Directory root,
  required StringSink out,
  required StringSink err,
}) {
  final problems = checkCiMatrix(root);
  if (problems.isEmpty) {
    out.writeln('CI matrix check passed.');
    return 0;
  }
  problems.forEach(err.writeln);
  err.writeln('CI matrix check failed: ${problems.length} problem(s).');
  return 1;
}

class _Member {
  const new({required this.path, required this.pubspec});

  final String path;
  final YamlMap pubspec;
}

YamlMap _load(String path) =>
    loadYaml(File(path).readAsStringSync()) as YamlMap;

/// The value at [keys] under [map], or null where a key is missing.
Object? _path(YamlMap map, List<String> keys) {
  Object? value = map;
  for (final key in keys) {
    value = value is YamlMap ? value[key] : null;
  }
  return value;
}

/// Whether [name] needs the Flutter SDK, as melos' `flutter` filter decides:
/// directly, or through a workspace package it depends on.
bool _needsFlutter(String name, Map<String, _Member> members) {
  final dependencies = members[name]!.pubspec['dependencies'] as YamlMap?;
  return (dependencies?.keys ?? const []).any(
    (dependency) =>
        dependency == 'flutter' ||
        (members.containsKey(dependency) &&
            _needsFlutter(dependency as String, members)),
  );
}

bool _hasMacosOnlyTests(Directory tests) => tests
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => file.path.endsWith('_test.dart'))
    .any((file) => _macosOnlyTag.hasMatch(file.readAsStringSync()));

void _checkWorkflow(
  Directory root,
  String workflow,
  Map<String, String> scripts,
  Iterable<String> required,
  List<String> problems,
) {
  final file = File(p.join(root.path, workflow));
  final include = file.existsSync()
      ? _path(_load(file.path), [
          'jobs',
          'coverage',
          'strategy',
          'matrix',
          'include',
        ])
      : null;
  if (include is! YamlList) {
    problems.add('$workflow: no jobs.coverage.strategy.matrix.include');
    return;
  }

  final listed = <String>{};
  for (final entry in include) {
    final package = _path(entry as YamlMap, ['package']);
    final script = _path(entry, ['script']);
    final expected = scripts[package];
    if (!listed.add('$package')) {
      problems.add('$workflow: $package is listed twice');
    } else if (expected == null) {
      problems.add('$workflow: $package is not a workspace package with tests');
    } else if (script != expected) {
      problems.add(
        '$workflow: $package must run test:coverage:$expected, '
        'not test:coverage:$script',
      );
    }
  }
  for (final package in required) {
    if (!listed.contains(package)) {
      problems.add(
        '$workflow: $package is missing; add it to the coverage matrix with '
        'script: ${scripts[package]}',
      );
    }
  }
}

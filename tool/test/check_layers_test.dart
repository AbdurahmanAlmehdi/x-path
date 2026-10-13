import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xp_tool/xp_tool.dart';

/// A throwaway pub workspace on disk.
class _Workspace {
  new(Map<String, List<String>> members)
    : root = Directory.systemTemp.createTempSync('xp_layers_') {
    file('pubspec.yaml', [
      'name: root',
      'workspace:',
      for (final path in members.keys) '  - $path',
    ]);
    members.forEach((path, dependencies) {
      file('$path/pubspec.yaml', [
        'name: ${p.basename(path)}',
        if (dependencies.isNotEmpty) 'dependencies:',
        for (final dependency in dependencies) '  $dependency: any',
      ]);
    });
  }

  final Directory root;

  void file(String path, List<String> lines) {
    File(p.join(root.path, path))
      ..createSync(recursive: true)
      ..writeAsStringSync('${lines.join('\n')}\n');
  }

  void delete() => root.deleteSync(recursive: true);
}

/// Creates a [_Workspace] that is deleted when the current test ends.
_Workspace _workspace(Map<String, List<String>> members) {
  final workspace = _Workspace(members);
  addTearDown(workspace.delete);
  return workspace;
}

void main() {
  late _Workspace workspace;

  group('checkLayers', () {
    test('accepts a workspace that follows the rules', () {
      workspace =
          _Workspace({
              'packages/xp_api': [],
              'packages/xp_engine': ['xp_api'],
              'packages/xp_adapters': ['xp_engine', 'shelf'],
            })
            ..file('packages/xp_engine/lib/a.dart', [
              "import 'package:xp_api/xp_api.dart';",
              "import 'package:xp_engine/src/b.dart';",
              "import 'dart:io';",
              "import 'b.dart' if (dart.library.io) 'c.dart';",
              "export 'package:meta/meta.dart';",
              "// import 'package:shelf/shelf.dart';",
            ])
            ..file('packages/xp_engine/test/a_test.dart', [
              "import 'package:test/test.dart';",
              "import '../lib/a.dart';",
            ])
            ..file('packages/xp_adapters/lib/a.dart', [
              "import 'package:shelf/shelf.dart';",
              "import 'package:xp_engine/xp_engine.dart';",
            ]);

      expect(checkLayers(workspace.root), isEmpty);
    });

    test('rejects shelf imported from an xp_engine test file', () {
      workspace =
          _Workspace({
            'packages/xp_api': [],
            'packages/xp_engine': ['xp_api'],
          })..file('packages/xp_engine/test/engine_test.dart', [
            "import 'package:test/test.dart';",
            '',
            "import 'package:shelf/shelf.dart';",
          ]);

      final violation = checkLayers(workspace.root).single;

      expect(violation.location, 'packages/xp_engine/test/engine_test.dart:3');
      expect(
        violation.message,
        startsWith(
          'xp_engine must not depend on shelf (allowed external packages: ',
        ),
      );
    });

    test('reports the line where a multi-line directive starts', () {
      workspace =
          _Workspace({
            'packages/xp_api': [],
            'packages/xp_engine': ['xp_api'],
          })..file('packages/xp_engine/lib/a.dart', [
            'library;',
            '',
            'export',
            "    'package:shelf/shelf.dart'",
            '    show Request;',
          ]);

      expect(
        checkLayers(workspace.root).single.location,
        'packages/xp_engine/lib/a.dart:3',
      );
    });

    test('rejects a workspace package the layer may not use', () {
      workspace =
          _Workspace({
            'packages/xp_api': [],
            'packages/xp_engine': ['xp_api'],
            'packages/xp_adapters': ['xp_engine'],
          })..file('packages/xp_engine/lib/a.dart', [
            "import 'package:xp_adapters/xp_adapters.dart';",
          ]);

      final violation = checkLayers(workspace.root).single;

      expect(violation.location, 'packages/xp_engine/lib/a.dart:1');
      expect(
        violation.message,
        'xp_engine must not depend on xp_adapters '
        '(allowed workspace packages: xp_api)',
      );
    });

    test('rejects a desktop that reaches past the repositories', () {
      workspace =
          _Workspace({
            'packages/xp_api': [],
            'packages/xp_engine': ['xp_api'],
            'apps/xp_desktop': ['xp_api', 'xp_engine'],
          })..file('apps/xp_desktop/lib/a.dart', [
            "import 'package:xp_engine/xp_engine.dart';",
          ]);

      expect(checkLayers(workspace.root).map((v) => v.location), [
        'apps/xp_desktop/lib/a.dart:1',
        'apps/xp_desktop/pubspec.yaml',
      ]);
    });

    test('rejects a package that is not allowed in pubspec.yaml', () {
      workspace = _workspace({
        'packages/xp_api': ['shelf'],
      });

      final violation = checkLayers(workspace.root).single;

      expect(violation.location, 'packages/xp_api/pubspec.yaml');
      expect(violation.message, contains('xp_api must not depend on shelf'));
    });

    test('rejects a relative import that leaves the package', () {
      workspace =
          _Workspace({
            'packages/xp_api': [],
            'packages/xp_engine': ['xp_api'],
          })..file('packages/xp_engine/lib/a.dart', [
            "import '../../xp_adapters/lib/xp_adapters.dart';",
          ]);

      final violation = checkLayers(workspace.root).single;

      expect(violation.location, 'packages/xp_engine/lib/a.dart:1');
      expect(
        violation.message,
        'xp_engine must not import ../../xp_adapters/lib/xp_adapters.dart: '
        'it points outside the package',
      );
    });

    test('rejects a workspace package without a rule', () {
      workspace = _workspace({'packages/mystery': []});

      final violation = checkLayers(workspace.root).single;

      expect(violation.location, 'packages/mystery/pubspec.yaml');
      expect(
        violation.message,
        'no layer rule for mystery; add it to layerRules in '
        'tool/lib/src/layer_rules.dart',
      );
    });

    test('rejects a workspace entry without a pubspec', () {
      workspace = _workspace({'packages/xp_api': []});
      File(p.join(workspace.root.path, 'packages/xp_api/pubspec.yaml'))
          .deleteSync();

      final violation = checkLayers(workspace.root).single;

      expect(violation.location, 'packages/xp_api/pubspec.yaml');
      expect(violation.message, 'listed in the workspace but missing');
    });

    test('uses the rules it is given', () {
      workspace = _workspace({'packages/mystery': []});

      final violations = checkLayers(
        workspace.root,
        rules: {'mystery': const LayerRule(workspace: {})},
      );

      expect(violations, isEmpty);
    });
  });

  group('LayerViolation', () {
    test('prints its location and message', () {
      const violation = LayerViolation(location: 'a.dart:1', message: 'oops');

      expect(violation.toString(), 'a.dart:1: oops');
    });
  });

  group('runCheckLayers', () {
    late StringBuffer out;
    late StringBuffer err;

    setUp(() {
      out = StringBuffer();
      err = StringBuffer();
    });

    test('exits 0 and says so when nothing is wrong', () {
      workspace = _workspace({'packages/xp_api': []});

      final code = runCheckLayers(root: workspace.root, out: out, err: err);

      expect(code, 0);
      expect(out.toString(), 'Layer check passed.\n');
      expect(err.toString(), isEmpty);
    });

    test('exits 1 and lists every violation', () {
      workspace = _workspace({'packages/mystery': []});

      final code = runCheckLayers(root: workspace.root, out: out, err: err);

      expect(code, 1);
      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        allOf(
          contains('no layer rule for mystery'),
          endsWith('Layer check failed: 1 violation(s).\n'),
        ),
      );
    });
  });
}

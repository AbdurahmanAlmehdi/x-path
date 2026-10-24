import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xp_tool/xp_tool.dart';

/// A throwaway pub workspace with the two workflows on disk.
class _Workspace {
  new() : root = Directory.systemTemp.createTempSync('xp_ci_matrix_') {
    addTearDown(() => root.deleteSync(recursive: true));
    file('pubspec.yaml', [
      'name: root',
      'workspace:',
      '  - packages/xp_api',
      '  - packages/xp_secrets',
      '  - packages/xp_ui',
      '  - apps/xp_desktop',
      '  - tool',
      'melos:',
      '  scripts:',
      '    test:coverage:strict:',
      '      packageFilters:',
      '        scope:',
      '          - xp_api',
    ]);
    member('packages/xp_api');
    member('packages/xp_secrets', test: "@Tags(['macos'])");
    member('packages/xp_ui', dependencies: {'flutter': '{sdk: flutter}'});
    member('apps/xp_desktop', dependencies: {'xp_ui': 'any'});
    member('tool', test: null);
    workflow(gateWorkflow, {
      'xp_api': 'strict',
      'xp_secrets': 'floor',
      'xp_ui': 'flutter',
      'xp_desktop': 'flutter',
    });
    workflow(macosWorkflow, {
      'xp_secrets': 'floor',
      'xp_ui': 'flutter',
      'xp_desktop': 'flutter',
    });
  }

  final Directory root;

  void file(String path, List<String> lines) {
    File(p.join(root.path, path))
      ..createSync(recursive: true)
      ..writeAsStringSync('${lines.join('\n')}\n');
  }

  /// A member at [path]; [test] is the first line of its one test file, and
  /// a null [test] leaves it without a `test/` directory.
  void member(
    String path, {
    Map<String, String> dependencies = const {},
    String? test = "import 'package:test/test.dart';",
  }) {
    file('$path/pubspec.yaml', [
      'name: ${p.basename(path)}',
      if (dependencies.isNotEmpty) 'dependencies:',
      for (final MapEntry(:key, :value) in dependencies.entries)
        '  $key: $value',
    ]);
    if (test != null) file('$path/test/a_test.dart', [test]);
  }

  void workflow(String path, Map<String, String> scripts) {
    file(path, [
      'jobs:',
      '  coverage:',
      '    strategy:',
      '      matrix:',
      '        include:',
      for (final MapEntry(:key, :value) in scripts.entries)
        '          - { package: $key, script: $value }',
    ]);
  }
}

/// The problems [checkCiMatrix] finds at [root], one per line.
String _problems(Directory root) => checkCiMatrix(root).join('\n');

void main() {
  group('checkCiMatrix', () {
    test('accepts matrices that match the workspace', () {
      expect(checkCiMatrix(_Workspace().root), isEmpty);
    });

    test('accepts a macOS matrix with more packages than it needs', () {
      final workspace = _Workspace()
        ..workflow(macosWorkflow, {
          'xp_api': 'strict',
          'xp_secrets': 'floor',
          'xp_ui': 'flutter',
          'xp_desktop': 'flutter',
        });

      expect(checkCiMatrix(workspace.root), isEmpty);
    });

    test('rejects a package missing from the gate matrix', () {
      final workspace = _Workspace()
        ..workflow(gateWorkflow, {
          'xp_api': 'strict',
          'xp_ui': 'flutter',
          'xp_desktop': 'flutter',
        });

      expect(
        _problems(workspace.root),
        '.github/workflows/gate.yaml: xp_secrets is missing; add it to the '
        'coverage matrix with script: floor',
      );
    });

    test('rejects a package with macOS-only tests missing on macOS', () {
      final workspace = _Workspace()
        ..workflow(macosWorkflow, {'xp_ui': 'flutter'});

      expect(
        _problems(workspace.root),
        '.github/workflows/macos.yaml: xp_desktop is missing; add it to the '
        'coverage matrix with script: flutter\n'
        '.github/workflows/macos.yaml: xp_secrets is missing; add it to the '
        'coverage matrix with script: floor',
      );
    });

    test('rejects a package that runs with the wrong threshold', () {
      final workspace = _Workspace()
        ..workflow(gateWorkflow, {
          'xp_api': 'floor',
          'xp_secrets': 'floor',
          'xp_ui': 'flutter',
          'xp_desktop': 'floor',
        });

      expect(
        _problems(workspace.root),
        '.github/workflows/gate.yaml: xp_api must run test:coverage:strict, '
        'not test:coverage:floor\n'
        '.github/workflows/gate.yaml: xp_desktop must run '
        'test:coverage:flutter, not test:coverage:floor',
      );
    });

    test('rejects a package listed twice', () {
      final workspace = _Workspace()
        ..file(macosWorkflow, [
          'jobs:',
          '  coverage:',
          '    strategy:',
          '      matrix:',
          '        include:',
          '          - { package: xp_secrets, script: floor }',
          '          - { package: xp_secrets, script: floor }',
          '          - { package: xp_ui, script: flutter }',
          '          - { package: xp_desktop, script: flutter }',
        ]);

      expect(
        _problems(workspace.root),
        '.github/workflows/macos.yaml: xp_secrets is listed twice',
      );
    });

    test('rejects a package that is not a workspace package with tests', () {
      final workspace = _Workspace()
        ..workflow(macosWorkflow, {
          'tool': 'floor',
          'xp_secrets': 'floor',
          'xp_ui': 'flutter',
          'xp_desktop': 'flutter',
        });

      expect(
        _problems(workspace.root),
        '.github/workflows/macos.yaml: tool is not a workspace package with '
        'tests',
      );
    });

    test('rejects a workflow without a coverage matrix', () {
      final workspace = _Workspace()..file(gateWorkflow, ['jobs: {}']);
      File(p.join(workspace.root.path, macosWorkflow)).deleteSync();

      expect(
        _problems(workspace.root),
        '.github/workflows/gate.yaml: no jobs.coverage.strategy.matrix.include\n'
        '.github/workflows/macos.yaml: '
        'no jobs.coverage.strategy.matrix.include',
      );
    });

    test('rejects a workspace entry without a pubspec', () {
      final workspace = _Workspace();
      File(p.join(workspace.root.path, 'packages/xp_secrets/pubspec.yaml'))
          .deleteSync();

      expect(
        _problems(workspace.root),
        '.github/workflows/gate.yaml: xp_secrets is not a workspace package '
        'with tests\n'
        '.github/workflows/macos.yaml: xp_secrets is not a workspace package '
        'with tests\n'
        'packages/xp_secrets: listed in the workspace but has no pubspec.yaml',
      );
    });
  });

  group('runCheckCiMatrix', () {
    test('passes and says so', () {
      final out = StringBuffer();
      final err = StringBuffer();

      final code = runCheckCiMatrix(
        root: _Workspace().root,
        out: out,
        err: err,
      );

      expect(code, 0);
      expect(out.toString(), 'CI matrix check passed.\n');
      expect(err.toString(), isEmpty);
    });

    test('fails and lists the problems', () {
      final workspace = _Workspace()..file(gateWorkflow, ['jobs: {}']);
      final out = StringBuffer();
      final err = StringBuffer();

      final code = runCheckCiMatrix(root: workspace.root, out: out, err: err);

      expect(code, 1);
      expect(out.toString(), isEmpty);
      expect(
        err.toString(),
        '.github/workflows/gate.yaml: no jobs.coverage.strategy.matrix.include\n'
        'CI matrix check failed: 1 problem(s).\n',
      );
    });
  });
}

import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../../../helpers/guard_harness.dart';
import '../../../../helpers/stub_git.dart';
import '../../../../helpers/version_fixtures.dart';

void main() {
  const check = SourceCheck();

  test('names itself source', () => expect(check.name, GuardCheckName.source));

  group('passes', () {
    test('for a clean worktree on the dispatched commit', () async {
      final harness = guardRequest();

      final result = await check.run(harness.request);

      expect(result.status, GuardStatus.passed);
      expect(result.message, contains('committed'));
    });

    test('with untracked files outside the build inputs', () async {
      final git = StubGit()
        ..statusResult = const GitWorktreeStatus(
          headSha: dispatchedSha,
          untracked: ['notes.txt', 'build/app/outputs/app.aab', 'docs/todo.md'],
        );

      final result = await check.run(guardRequest(git: git).request);

      expect(result.status, GuardStatus.passed);
    });

    test('with a lock file that only has hosted packages', () async {
      final harness = guardRequest(
        files: {
          ...customerApp('5.4.1+3283'),
          'pubspec.lock': '''
packages:
  mataa_core:
    dependency: "direct main"
    description:
      path: "."
      ref: main
      resolved-ref: "0123456789abcdef"
      url: "https://github.com/mataa/mataa_core.git"
    source: git
    version: "2.0.0"
''',
        },
      );

      expect((await check.run(harness.request)).status, GuardStatus.passed);
    });

    // Incident: Lina's own UI package, committed under packages/lina_ui,
    // failed the guard as a local path dependency.
    test('for a relative path package committed in the repository '
        '(real incident)', () async {
      final git = StubGit()
        ..statusResult = const GitWorktreeStatus(
          headSha: dispatchedSha,
          untracked: ['packages/other/notes.txt'],
        );
      final harness = guardRequest(git: git, files: _linaApp);

      final result = await check.run(harness.request);

      expect(result.status, GuardStatus.passed);
    });

    test('for a monorepo app whose package sits beside it', () async {
      final harness = guardRequest(
        appPath: 'apps/captain',
        files: {
          'apps/captain/pubspec.yaml': pubspec('1.0.0+1'),
          'apps/captain/pubspec.lock': _lock('core', '../../packages/core'),
          'packages/core/pubspec.yaml': '',
          'pubspec.lock': _lock('captain', './apps/captain'),
        },
        versionFiles: ['apps/captain/pubspec.yaml'],
      );

      expect((await check.run(harness.request)).status, GuardStatus.passed);
    });

    test('for a lock file without packages', () async {
      final harness = guardRequest(
        files: {...customerApp('5.4.1+3283'), 'pubspec.lock': 'sdks: {}'},
      );

      expect((await check.run(harness.request)).status, GuardStatus.passed);
    });
  });

  group('fails', () {
    // Incident: a build was made with pubspec_overrides.yaml pointing the core
    // package at a local checkout, so the shipped source existed only on one
    // Mac (R:141-146).
    test('when pubspec_overrides.yaml is present (real incident)', () async {
      final harness = guardRequest(
        files: {
          ...customerApp('5.4.1+3283'),
          'pubspec_overrides.yaml': '''
# melos_managed_dependency_overrides: mataa_core
dependency_overrides:
  mataa_core:
    path: ../mataa_core
''',
        },
      );

      final result = await check.run(harness.request);

      expect(result.status, GuardStatus.failed);
      expect(result.message, contains('pubspec_overrides.yaml is active'));
      expect(
        result.fix,
        'Remove pubspec_overrides.yaml. A release builds only what is in git.',
      );
    });

    // Incident: a debug file under lib/ that was never committed was
    // compiled into a production build (R:121-128).
    test('when an untracked file sits in lib/ (real incident)', () async {
      final git = StubGit()
        ..statusResult = const GitWorktreeStatus(
          headSha: dispatchedSha,
          untracked: ['lib/features/debug/force_prod_flags.dart'],
        );

      final result = await check.run(guardRequest(git: git).request);

      expect(result.status, GuardStatus.failed);
      expect(
        result.message,
        'Untracked file: lib/features/debug/force_prod_flags.dart',
      );
    });

    test('for untracked files in assets, ios and android', () async {
      final git = StubGit()
        ..statusResult = const GitWorktreeStatus(
          headSha: dispatchedSha,
          untracked: [
            'assets/images/draft.png',
            'ios/Runner/Debug.xcconfig',
            'android/key.properties',
            'pubspec.yaml',
          ],
        );

      final result = await check.run(guardRequest(git: git).request);

      expect(result.message.split('\n'), hasLength(4));
    });

    test('for an uncommitted change to a tracked file', () async {
      final git = StubGit()
        ..statusResult = const GitWorktreeStatus(
          headSha: dispatchedSha,
          changed: ['lib/main.dart'],
        );

      final result = await check.run(guardRequest(git: git).request);

      expect(result.status, GuardStatus.failed);
      expect(result.message, 'Uncommitted change: lib/main.dart');
    });

    test('when HEAD is not the dispatched commit', () async {
      final git = StubGit()
        ..statusResult = const GitWorktreeStatus(headSha: otherSha);
      final harness = guardRequest(git: git);

      final result = await check.run(harness.request);

      expect(result.status, GuardStatus.failed);
      expect(
        result.message,
        'HEAD is $otherSha, not the dispatched commit $dispatchedSha.',
      );
    });

    test('for a path package outside the repository', () async {
      final harness = guardRequest(
        files: {
          ...customerApp('5.4.1+3283'),
          'pubspec.lock': _lock('mataa_core', '../mataa_core'),
        },
      );

      final result = await check.run(harness.request);

      expect(result.status, GuardStatus.failed);
      expect(
        result.message,
        'pubspec.lock resolves the path package mataa_core from '
        '../mataa_core, outside the repository.',
      );
      expect(
        result.fix,
        'Take mataa_core from git, a hosted version or a relative path '
        'inside the repository, and run pub get. A release builds only what '
        'is in git.',
      );
    });

    test('for a path that climbs out of a monorepo app', () async {
      final harness = guardRequest(
        appPath: 'apps/captain',
        files: {
          'apps/captain/pubspec.yaml': pubspec('1.0.0+1'),
          'apps/captain/pubspec.lock': _lock('core', '../../../core'),
        },
        versionFiles: ['apps/captain/pubspec.yaml'],
      );

      expect(
        (await check.run(harness.request)).message,
        'apps/captain/pubspec.lock resolves the path package core from '
        '../../../core, outside the repository.',
      );
    });

    test('for a path package with an absolute path', () async {
      final harness = guardRequest(
        files: {
          ...customerApp('5.4.1+3283'),
          'pubspec.lock': _lock(
            'mataa_core',
            '/Users/dev/mataa_core',
            relative: false,
          ),
        },
      );

      final result = await check.run(harness.request);

      expect(result.status, GuardStatus.failed);
      expect(
        result.message,
        'pubspec.lock resolves the path package mataa_core from the absolute '
        'path /Users/dev/mataa_core.',
      );
      expect(result.fix, startsWith('Take mataa_core from git'));
    });

    test('for a relative path that starts at the root', () async {
      final harness = guardRequest(
        files: {
          ...customerApp('5.4.1+3283'),
          'pubspec.lock': _lock('ui', '/ui'),
        },
      );

      expect(
        (await check.run(harness.request)).message,
        'pubspec.lock resolves the path package ui from the absolute path '
        '/ui.',
      );
    });

    test('for a path package whose lock entry names no path', () async {
      final harness = guardRequest(
        files: {
          ...customerApp('5.4.1+3283'),
          'pubspec.lock': '''
packages:
  ui:
    dependency: "direct main"
    description: "packages/ui"
    source: path
''',
        },
      );

      final result = await check.run(harness.request);

      expect(
        result.message,
        'pubspec.lock resolves the path package ui without naming its path.',
      );
      expect(result.fix, startsWith('Take ui from git'));
    });

    test('for a path package that is not in the worktree', () async {
      final harness = guardRequest(
        files: {
          ...customerApp('5.4.1+3283'),
          'pubspec.lock': _lock('lina_ui', 'packages/lina_ui'),
        },
      );

      final result = await check.run(harness.request);

      expect(result.status, GuardStatus.failed);
      expect(
        result.message,
        'pubspec.lock resolves the path package lina_ui from '
        'packages/lina_ui, which is not in the worktree.',
      );
      expect(
        result.fix,
        'Commit the folder of lina_ui, or fix its path in pubspec.yaml and '
        'run pub get. A release builds only what is in git.',
      );
    });

    test('for an untracked file under an in-repo path package', () async {
      final git = StubGit()
        ..statusResult = const GitWorktreeStatus(
          headSha: dispatchedSha,
          untracked: ['packages/lina_ui/lib/src/draft.dart'],
        );
      final harness = guardRequest(git: git, files: _linaApp);

      final result = await check.run(harness.request);

      expect(result.status, GuardStatus.failed);
      expect(result.message.split('\n'), [
        'Untracked file: packages/lina_ui/lib/src/draft.dart',
        _linaDirty,
      ]);
      expect(
        result.fix,
        'Commit or discard the changes. A release builds only what is in git.',
      );
    });

    test('for a modified file under an in-repo path package', () async {
      final git = StubGit()
        ..statusResult = const GitWorktreeStatus(
          headSha: dispatchedSha,
          changed: ['packages/lina_ui/lib/lina_ui.dart'],
        );
      final harness = guardRequest(git: git, files: _linaApp);

      final result = await check.run(harness.request);

      expect(result.message.split('\n'), [
        'Uncommitted change: packages/lina_ui/lib/lina_ui.dart',
        _linaDirty,
      ]);
    });

    test('for a lock file that is not YAML', () async {
      final harness = guardRequest(
        files: {...customerApp('5.4.1+3283'), 'pubspec.lock': 'packages: ['},
      );

      final result = await check.run(harness.request);

      expect(result.status, GuardStatus.failed);
      expect(
        result.message,
        'pubspec.lock is not valid YAML, so its path packages cannot be '
        'checked.',
      );
      expect(
        result.fix,
        'Run pub get to write pubspec.lock again. A release builds only what '
        'is in git.',
      );
    });

    test('for the app folder and the repository root of a monorepo', () async {
      final git = StubGit()
        ..statusResult = const GitWorktreeStatus(
          headSha: dispatchedSha,
          untracked: ['apps/captain/lib/x.dart', 'lib/not_the_app.dart'],
        );
      final harness = guardRequest(
        git: git,
        appPath: 'apps/captain',
        files: {
          'apps/captain/pubspec.yaml': pubspec('1.0.0+1'),
          'pubspec_overrides.yaml': 'dependency_overrides: {}',
        },
        versionFiles: ['apps/captain/pubspec.yaml'],
      );

      final result = await check.run(harness.request);

      expect(result.message.split('\n'), [
        'Untracked file: apps/captain/lib/x.dart',
        _overridesMessage,
      ]);
    });

    test('and lists every problem at once', () async {
      final git = StubGit()
        ..statusResult = const GitWorktreeStatus(
          headSha: otherSha,
          changed: ['pubspec.yaml'],
          untracked: ['lib/a.dart'],
        );
      final harness = guardRequest(
        git: git,
        files: {...customerApp('5.4.1+3283'), 'pubspec_overrides.yaml': ''},
      );
      final result = await check.run(harness.request);

      expect(result.message.split('\n'), hasLength(4));
    });
  });
}

const _linaDirty =
    'pubspec.lock resolves the path package lina_ui from packages/lina_ui, '
    'which has uncommitted or untracked files.';

final Map<String, String> _linaApp = {
  ...customerApp('5.4.1+3283'),
  'pubspec.lock': _lock('lina_ui', 'packages/lina_ui'),
  'packages/lina_ui/pubspec.yaml': 'name: lina_ui',
  'packages/lina_ui/lib/lina_ui.dart': '',
};

/// A lock file with the one path package [name] at [path].
String _lock(String name, String path, {bool relative = true}) =>
    '''
packages:
  $name:
    dependency: "direct main"
    description:
      path: "$path"
      relative: $relative
    source: path
    version: "1.0.0"
''';

const _overridesMessage =
    'pubspec_overrides.yaml is active. Its dependency_overrides replace the '
    'ones in pubspec.yaml and can point at local checkouts.';

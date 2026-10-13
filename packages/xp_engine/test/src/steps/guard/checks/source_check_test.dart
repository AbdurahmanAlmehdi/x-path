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
      expect(result.fix, contains('remove pubspec_overrides.yaml'));
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

    test('when the lock file resolves a package from a local path', () async {
      final harness = guardRequest(
        files: {
          ...customerApp('5.4.1+3283'),
          'pubspec.lock': '''
packages:
  mataa_core:
    dependency: "direct main"
    description:
      path: "../mataa_core"
      relative: true
    source: path
    version: "2.0.0"
''',
        },
      );

      final result = await check.run(harness.request);

      expect(result.status, GuardStatus.failed);
      expect(
        result.message,
        'pubspec.lock resolves a package from a local path.',
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

const _overridesMessage =
    'pubspec_overrides.yaml is active. Its dependency_overrides replace the '
    'ones in pubspec.yaml and can point at local checkouts.';

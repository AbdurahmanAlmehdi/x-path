// Equal constants are identical and never compare props, so these tests
// build their values at run time.
// ignore_for_file: prefer_const_constructors
// ignore_for_file: prefer_const_literals_to_create_immutables

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

import '../../helpers/repo_builder.dart';

List<String> codes(ScanResult result) => [
  for (final finding in result.findings) finding.code,
];

void main() {
  group('layout', () {
    test('a folder with nothing in it has no app', () async {
      final result = await scanFiles({'README.md': ''});

      expect(result.profile.apps, isEmpty);
      expect(result.profile.layout, ProjectLayout.single);
      expect(result.findings.single.code, 'no_flutter_app');
      expect(result.findings.single.severity, FindingSeverity.error);
      expect(result.findings.single.fix, isNotEmpty);
    });

    test('a pubspec that is not YAML is an error', () async {
      final result = await scanFiles({'pubspec.yaml': 'a: [b'});

      expect(codes(result), ['pubspec_invalid', 'no_flutter_app']);
      expect(result.findings.first.path, 'pubspec.yaml');
    });

    test('an app at the root is a single app', () async {
      final result = await scanFiles(app());

      expect(result.profile.layout, ProjectLayout.single);
      expect(result.profile.apps.single.path, '.');
      expect(result.profile.apps.single.name, 'demo');
    });

    test('Dart packages, plugins and apps without platforms are not apps', () {
      return expectLater(
        scanFiles({
          'pubspec.yaml': 'name: ws\nworkspace:\n  - packages/*\n',
          ...app(dir: 'packages/real'),
          'packages/plain/pubspec.yaml': 'name: plain\n',
          ...app(
            dir: 'packages/plugin',
            overrides: {
              'pubspec.yaml': pubspec(
                name: 'plugin',
                extra: 'flutter:\n  plugin:\n    platforms: {}\n',
              ),
            },
          ),
          ...app(
            dir: 'packages/webonly',
            overrides: {
              'android/app/build.gradle': null,
              'android/key.properties': null,
              'ios/Runner.xcodeproj/project.pbxproj': null,
              'ios/Runner/Info.plist': null,
              'ios/Podfile': null,
            },
          ),
          ...app(
            dir: 'packages/noname',
            overrides: {'pubspec.yaml': 'dependencies:\n  flutter:\n'},
          ),
        }).then((result) => result.profile.apps.map((a) => a.path)),
        completion(['packages/real']),
      );
    });

    test('workspace members and melos globs name the apps', () async {
      final result = await scanFiles({
        'pubspec.yaml': '''
name: ws
workspace:
  - apps/one/
  - tools/not_an_app
melos:
  packages:
    - apps/*
    - '!apps/skipped'
    - packages/**
    - ../outside
    - ''
''',
        ...app(
          dir: 'apps/one',
          overrides: {'pubspec.yaml': pubspec(name: 'one')},
        ),
        ...app(
          dir: 'apps/two',
          overrides: {'pubspec.yaml': pubspec(name: 'two')},
        ),
        ...app(dir: 'apps/skipped'),
        ...app(
          dir: 'packages/three',
          overrides: {'pubspec.yaml': pubspec(name: 'three')},
        ),
        'apps/file.txt': '',
      });

      expect(result.profile.layout, ProjectLayout.melos);
      expect(result.profile.apps.map((a) => a.name), ['one', 'two', 'three']);
    });

    test(
      'melos.yaml works for a repository without a pubspec workspace',
      () async {
        final result = await scanFiles({
          'melos.yaml': 'name: m\npackages:\n  - apps/*\n',
          ...app(dir: 'apps/one'),
        });

        expect(result.profile.layout, ProjectLayout.melos);
        expect(result.profile.apps.single.path, 'apps/one');
      },
    );

    test('an app that is also a member is scanned once', () async {
      final result = await scanFiles({
        ...app(
          overrides: {'pubspec.yaml': pubspec(extra: 'workspace:\n  - .\n')},
        ),
      });

      expect(result.profile.apps, hasLength(1));
    });

    test('a member with an invalid pubspec is a warning, not an app', () async {
      final result = await scanFiles({
        'pubspec.yaml': 'name: ws\nworkspace:\n  - apps/broken\n',
        'apps/broken/pubspec.yaml': 'a: [b',
        'apps/broken/android/app/build.gradle': '',
      });

      expect(codes(result), ['no_flutter_app', 'pubspec_invalid']);
      final invalid = result.findings.last;
      expect(invalid.severity, FindingSeverity.warning);
      expect(invalid.path, 'apps/broken/pubspec.yaml');
    });
  });

  group('findings', () {
    test('come most severe first, in the order they were noticed', () async {
      final result = await scanFiles(
        app(
          overrides: {
            '.fvmrc': null,
            'android/key.properties': null,
            'pubspec.yaml': pubspec(version: null),
            'ios/Runner/Info.plist': plist(shortVersion: '1.0.0', build: '1'),
          },
        ),
      );

      expect(
        result.findings.map((finding) => finding.severity),
        [...result.findings.map((finding) => finding.severity)]
          ..sort((a, b) => a.index - b.index),
      );
      expect(codes(result).first, 'pubspec_version_missing');
      expect(
        codes(result).skip(1),
        containsAll([
          'keystore_properties_missing',
          'plist_literal_version',
          'fvmrc_missing',
        ]),
      );
    });

    test('every finding has a fix', () async {
      final result = await scanFiles({'a': 'b'});

      expect(
        result.findings.every((finding) => finding.fix.isNotEmpty),
        isTrue,
      );
    });
  });

  group('branches', () {
    test('are empty when the folder is not a clone', () async {
      final result = await scanFiles(app());

      expect(result.profile.branches, const BranchLayout());
    });

    test('come from loose and packed refs of the clone', () async {
      final result = await scanFiles({
        ...app(),
        '.git/packed-refs': '''
# pack-refs with: peeled fully-peeled sorted
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa refs/heads/main
bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb refs/remotes/origin/release/2.0
^cccccccccccccccccccccccccccccccccccccccc
dddddddddddddddddddddddddddddddddddddddd refs/tags/v1.0.0
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee refs/remotes/origin/HEAD
malformed line with spaces
''',
        '.git/refs/heads/dev': 'ffff\n',
        '.git/refs/heads/release/1.0': 'ffff\n',
        '.git/refs/heads/feature/deep/x': 'ffff\n',
        '.git/refs/remotes/origin/HEAD': 'ref: refs/remotes/origin/dev\n',
        '.git/refs/remotes/origin/release/1.1': 'ffff\n',
        '.git/refs/remotes/upstream/release/9.9': 'ffff\n',
      });

      expect(
        result.profile.branches,
        const BranchLayout(
          defaultBranch: 'dev',
          releaseBranches: ['release/1.0', 'release/1.1', 'release/2.0'],
        ),
      );
      expect(result.profile.branches.hasReleaseBranches, isTrue);
    });

    test('stop looking in absurdly deep directories', () async {
      final deep = List.filled(9, 'd').join('/');
      final result = await scanFiles({
        ...app(),
        '.git/refs/heads/$deep/release/x': '',
      });

      expect(result.profile.branches.releaseBranches, isEmpty);
    });
  });

  group('workflows', () {
    test('lists GitHub Actions files and Codemagic configurations', () async {
      final result = await scanFiles({
        ...app(),
        '.github/workflows/ci.yml': 'name: CI\non: push\n',
        '.github/workflows/release.yaml': 'on: push\n',
        '.github/workflows/notes.txt': 'name: ignored',
        '.github/workflows/sub/ignored.yml': 'name: ignored',
        'codemagic.yaml': '''
workflows:
  ios:
    name: iOS release
  android: {}
  plain: scalar
''',
      });

      expect(result.profile.workflows, const [
        RepoWorkflow(
          path: '.github/workflows/ci.yml',
          provider: 'github_actions',
          names: ['CI'],
        ),
        RepoWorkflow(
          path: '.github/workflows/release.yaml',
          provider: 'github_actions',
          names: ['release'],
        ),
        RepoWorkflow(
          path: 'codemagic.yaml',
          provider: 'codemagic',
          names: ['iOS release', 'android', 'plain'],
        ),
      ]);
    });

    test('lists codemagic.yml and files without workflows', () async {
      final result = await scanFiles({
        ...app(),
        'codemagic.yml': 'definitions: {}\n',
        '.github/workflows/empty.yml': '',
      });

      expect(result.profile.workflows, const [
        RepoWorkflow(
          path: '.github/workflows/empty.yml',
          provider: 'github_actions',
          names: ['empty'],
        ),
        RepoWorkflow(path: 'codemagic.yml', provider: 'codemagic'),
      ]);
    });

    test('warns about a file that is not YAML and leaves it out', () async {
      final result = await scanFiles({
        ...app(),
        '.github/workflows/bad.yml': 'a: [b',
        'codemagic.yaml': 'a: [b',
      });

      expect(result.profile.workflows, isEmpty);
      final warnings = result.findings.where(
        (finding) => finding.code == 'workflow_yaml_invalid',
      );
      expect(warnings.map((finding) => finding.path), [
        '.github/workflows/bad.yml',
        'codemagic.yaml',
      ]);
      expect(
        warnings.every(
          (finding) => finding.severity == FindingSeverity.warning,
        ),
        isTrue,
      );
    });
  });

  test('ScanResult compares by value', () {
    ScanResult result() =>
        ScanResult(profile: const ProjectProfile(), findings: []);

    expect(result(), result());
  });
}

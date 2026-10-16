import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xp_tool/xp_tool.dart';

/// A [ReleaseHistory] with fixed answers.
class _FakeHistory implements ReleaseHistory {
  new({
    this.atHead = const [],
    this.merged = const [],
    this.since = const {},
    this.head = 'chore: something',
  });

  final List<String> atHead;
  final List<String> merged;
  final Map<String, List<String>> since;
  final String head;

  @override
  List<String> tagsAtHead() => atHead;

  @override
  List<String> mergedTags() => merged;

  @override
  List<String> messagesSince(String tag) => since[tag]!;

  @override
  String headMessage() => head;

  @override
  int commitCount() => 42;
}

const _v001 = ReleaseVersion(0, 0, 1);
const _v120 = ReleaseVersion(1, 2, 0);

/// A copy of the version files of the repository in a temporary folder.
Directory _checkout({
  String pubspec = 'name: app\nversion: 0.0.1\n',
  String constant = "const packageVersion = '0.0.1';\n",
}) {
  final root = Directory.systemTemp.createTempSync('xp_release_version_');
  addTearDown(() => root.deleteSync(recursive: true));
  void write(String path, String text) {
    File(p.join(root.path, path))
      ..createSync(recursive: true)
      ..writeAsStringSync(text);
  }

  for (final app in ['xpd', 'xp']) {
    write('apps/$app/pubspec.yaml', pubspec);
    write('apps/$app/lib/src/version.dart', '/// The version.\n$constant');
  }
  write(
    'apps/xp_desktop/pubspec.yaml',
    'name: xp_desktop\nversion: 0.0.1+1\npublish_to: none\n',
  );
  return root;
}

String _read(Directory root, String path) =>
    File(p.join(root.path, path)).readAsStringSync();

void main() {
  group('ReleaseVersion', () {
    test('parses plain versions with or without a v', () {
      expect('${ReleaseVersion.tryParse('1.2.3')}', '1.2.3');
      expect('${ReleaseVersion.tryParse(' v0.10.0 ')}', '0.10.0');
    });

    test('refuses pre-releases, builds and other text', () {
      expect(ReleaseVersion.tryParse('1.0.0-rc.1'), isNull);
      expect(ReleaseVersion.tryParse('1.2.3+4'), isNull);
      expect(ReleaseVersion.tryParse('1.2'), isNull);
      expect(ReleaseVersion.tryParse('latest'), isNull);
    });

    test('bumps', () {
      const version = ReleaseVersion(1, 4, 2);
      expect('${version.bumped(Bump.patch)}', '1.4.3');
      expect('${version.bumped(Bump.minor)}', '1.5.0');
      expect('${version.bumped(Bump.major)}', '2.0.0');
    });

    test('orders by major, then minor, then patch', () {
      final versions = [
        const ReleaseVersion(1, 0, 0),
        const ReleaseVersion(0, 10, 0),
        const ReleaseVersion(0, 9, 12),
        const ReleaseVersion(0, 10, 1),
      ]..sort();
      expect(versions.map((v) => '$v'), [
        '0.9.12',
        '0.10.0',
        '0.10.1',
        '1.0.0',
      ]);
    });
  });

  group('titleOf', () {
    test('is the first line of a commit', () {
      expect(
        titleOf('feat: add a thing (#12)\n\nbody'),
        'feat: add a thing (#12)',
      );
    });

    test('is the pull request title for a merge commit', () {
      expect(
        titleOf(
          'Merge pull request #12 from owner/branch\n\nfeat: add a thing\n',
        ),
        'feat: add a thing',
      );
    });

    test('keeps the merge line when the merge has no body', () {
      expect(
        titleOf("Merge branch 'x' into main"),
        "Merge branch 'x' into main",
      );
    });
  });

  group('bumpOf', () {
    <String, Bump>{
      'feat: retry Play uploads after a 503 (#41)': Bump.minor,
      'feat(desktop): add a sheet': Bump.minor,
      'Feat: capitalised type': Bump.minor,
      'fix: keep the log': Bump.patch,
      'perf: faster scans': Bump.patch,
      'docs: explain runners': Bump.patch,
      'test: cover the gate': Bump.patch,
      'ci: release on every merge to main': Bump.patch,
      'chore: bump packages': Bump.patch,
      'refactor: split the engine': Bump.patch,
      'build: pin flutter': Bump.patch,
      'style: format': Bump.patch,
      'revert: feat: something': Bump.patch,
      'not a conventional title': Bump.patch,
      'feature: not the feat type': Bump.patch,
      "Merge branch 'x' into main": Bump.patch,
      'Merge pull request #3 from a/b\n\nfeat: add a thing': Bump.minor,
      'Merge pull request #3 from a/b\n\nfix!: drop a flag': Bump.minor,
    }.forEach((message, bump) {
      test('${message.split('\n').last} is $bump before 1.0', () {
        expect(bumpOf(message, _v001), bump);
      });
    });

    test('a breaking change is minor before 1.0 and major after', () {
      for (final message in [
        'feat!: drop the v0 API',
        'fix(api)!: rename a field',
        'refactor: rename\n\nBREAKING CHANGE: the field is gone',
        'chore: rename\n\nBREAKING-CHANGE: the field is gone',
      ]) {
        expect(bumpOf(message, _v001), Bump.minor, reason: message);
        expect(bumpOf(message, _v120), Bump.major, reason: message);
      }
    });

    test('a feature is minor and a fix patch after 1.0 too', () {
      expect(bumpOf('feat: x', _v120), Bump.minor);
      expect(bumpOf('fix: x', _v120), Bump.patch);
    });

    test('a lower-case breaking change in the body is not a footer', () {
      expect(bumpOf('fix: x\n\nbreaking change: no', _v001), Bump.patch);
    });
  });

  group('planRelease', () {
    test('without a release tag bumps the pubspec version by HEAD', () {
      final plan = planRelease(
        history: _FakeHistory(head: 'feat: notarized DMG packaging'),
        pubspecVersion: _v001,
      );
      expect(plan.version, '0.1.0');
      expect(plan.tag, 'v0.1.0');
      expect(plan.build, 42);
      expect(plan.prerelease, isTrue);
      expect(plan.reason, contains('no release tag yet, base 0.0.1'));
    });

    test('without a release tag a fix is a patch of the pubspec version', () {
      final plan = planRelease(
        history: _FakeHistory(
          head: 'ci: release on every merge to main',
          merged: ['v0.0.0-rc.1', 'other'],
        ),
        pubspecVersion: _v001,
      );
      expect(plan.version, '0.0.2');
    });

    test('bumps the highest plain tag by the commits since it', () {
      final plan = planRelease(
        history: _FakeHistory(
          merged: ['v0.3.9', 'v0.4.2', 'v0.4.10-rc.1', 'v0.10.0', 'x0.99.0'],
          since: {
            'v0.10.0': ['fix: one'],
          },
        ),
        pubspecVersion: _v001,
      );
      expect(plan.version, '0.10.1');
      expect(plan.reason, 'after v0.10.0; 1 commit; patch bump');
    });

    test('takes the largest bump when runs were skipped', () {
      final plan = planRelease(
        history: _FakeHistory(
          merged: ['v0.4.2'],
          since: {
            'v0.4.2': ['fix: two', 'feat: one', 'docs: zero'],
          },
        ),
        pubspecVersion: _v001,
      );
      expect(plan.version, '0.5.0');
      expect(plan.reason, contains('3 commits; minor bump'));
    });

    test('a breaking change after 1.0 is a major release', () {
      final plan = planRelease(
        history: _FakeHistory(
          merged: ['v1.2.0'],
          since: {
            'v1.2.0': ['feat!: new API'],
          },
        ),
        pubspecVersion: _v001,
      );
      expect(plan.version, '2.0.0');
      expect(plan.prerelease, isFalse);
    });

    test('no commit since the tag is a patch', () {
      final plan = planRelease(
        history: _FakeHistory(merged: ['v0.4.2'], since: {'v0.4.2': []}),
        pubspecVersion: _v001,
      );
      expect(plan.version, '0.4.3');
    });

    test('a run again reuses the tag that points at HEAD', () {
      final plan = planRelease(
        history: _FakeHistory(
          atHead: ['v0.4.3', 'v0.4.2', 'vnext'],
          merged: ['v0.4.3'],
        ),
        pubspecVersion: _v001,
      );
      expect(plan.version, '0.4.3');
      expect(plan.reason, 'v0.4.3 already points at HEAD');
    });

    test('a tag pushed by hand is the release', () {
      final plan = planRelease(
        history: _FakeHistory(merged: ['v0.9.3'], since: {}),
        pubspecVersion: _v001,
        tag: 'v1.0.0',
      );
      expect(plan.version, '1.0.0');
      expect(plan.prerelease, isFalse);
      expect(plan.reason, 'tag v1.0.0');
    });

    test('a pre-release tag is a pre-release', () {
      final plan = planRelease(
        history: _FakeHistory(),
        pubspecVersion: _v001,
        tag: 'v1.0.0-rc.1',
      );
      expect(plan.version, '1.0.0-rc.1');
      expect(plan.prerelease, isTrue);
    });

    test('refuses a tag that is not a version', () {
      for (final tag in ['1.0.0', 'v1.0', 'v1.0.0+3', 'vnext']) {
        expect(
          () => planRelease(
            history: _FakeHistory(),
            pubspecVersion: _v001,
            tag: tag,
          ),
          throwsFormatException,
          reason: tag,
        );
      }
    });

    test('writes the GitHub output lines', () {
      const plan = ReleasePlan(version: '0.5.0', build: 7, reason: '');
      expect(
        plan.toOutput(),
        'version=0.5.0\ntag=v0.5.0\nbuild=7\nprerelease=true\n',
      );
    });
  });

  group('applyVersion', () {
    test('writes the version into the pubspecs and the constants', () {
      final root = _checkout();
      final written = applyVersion(root, '0.5.0', 128);
      expect(
        written,
        unorderedEquals([
          'apps/xpd/pubspec.yaml',
          'apps/xpd/lib/src/version.dart',
          'apps/xp/pubspec.yaml',
          'apps/xp/lib/src/version.dart',
          'apps/xp_desktop/pubspec.yaml',
        ]),
      );
      for (final app in ['xpd', 'xp']) {
        expect(
          _read(root, 'apps/$app/pubspec.yaml'),
          'name: app\nversion: 0.5.0\n',
        );
        expect(
          _read(root, 'apps/$app/lib/src/version.dart'),
          "/// The version.\nconst packageVersion = '0.5.0';\n",
        );
      }
      expect(
        _read(root, 'apps/xp_desktop/pubspec.yaml'),
        'name: xp_desktop\nversion: 0.5.0+128\npublish_to: none\n',
      );
    });

    test('takes a pre-release version', () {
      final root = _checkout();
      applyVersion(root, '1.0.0-rc.1', 3);
      expect(
        _read(root, 'apps/xp_desktop/pubspec.yaml'),
        contains('version: 1.0.0-rc.1+3\n'),
      );
    });

    test('refuses a bad version or build', () {
      final root = _checkout();
      expect(() => applyVersion(root, 'v0.5.0', 1), throwsFormatException);
      expect(() => applyVersion(root, '0.5', 1), throwsFormatException);
      expect(() => applyVersion(root, '0.5.0', 0), throwsFormatException);
    });

    test('writes nothing when a file lacks its version line', () {
      final root = _checkout(constant: 'const otherName = 1;\n');
      expect(
        () => applyVersion(root, '0.5.0', 1),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains(
              'apps/xpd/lib/src/version.dart holds its version line 0 times',
            ),
          ),
        ),
      );
      expect(_read(root, 'apps/xpd/pubspec.yaml'), contains('version: 0.0.1'));
    });
  });

  group('runReleaseVersion', () {
    late StringBuffer out;
    late StringBuffer err;

    setUp(() {
      out = StringBuffer();
      err = StringBuffer();
    });

    int run(
      List<String> arguments,
      Directory root, {
      ReleaseHistory? history,
    }) => runReleaseVersion(
      arguments,
      root: root,
      out: out,
      err: err,
      history: history ?? _FakeHistory(head: 'feat: x'),
    );

    test('next prints the plan and says why on stderr', () {
      expect(run(['next'], _checkout()), 0);
      expect(
        out.toString(),
        'version=0.1.0\ntag=v0.1.0\nbuild=42\nprerelease=true\n',
      );
      expect(
        err.toString(),
        contains('Release v0.1.0 (build 42): no release tag yet'),
      );
    });

    test('next --tag releases that tag', () {
      expect(run(['next', '--tag', 'v1.0.0'], _checkout()), 0);
      expect(out.toString(), startsWith('version=1.0.0\n'));
    });

    test('next fails on a bad tag', () {
      expect(run(['next', '--tag', 'one'], _checkout()), 1);
      expect(
        err.toString(),
        contains('release_version: the tag must be v<major>'),
      );
    });

    test('next fails without a plain pubspec version', () {
      expect(run(['next'], _checkout(pubspec: 'name: app\n')), 1);
      expect(
        err.toString(),
        contains('apps/xpd/pubspec.yaml has no plain version'),
      );
    });

    test('apply writes the version', () {
      final root = _checkout();
      expect(run(['apply', '0.2.0', '9'], root), 0);
      expect(
        out.toString(),
        startsWith('Version 0.2.0+9 written to apps/xpd/pubspec.yaml'),
      );
      expect(_read(root, 'apps/xp_desktop/pubspec.yaml'), contains('0.2.0+9'));
    });

    test('apply fails when a file lacks its version line', () {
      expect(run(['apply', '0.2.0', '9'], _checkout(constant: '')), 1);
      expect(err.toString(), contains('holds its version line 0 times'));
    });

    test('anything else prints the usage', () {
      for (final arguments in [
        <String>[],
        ['next', '--tag'],
        ['apply', '0.2.0'],
        ['apply', '0.2.0', 'nine'],
        ['publish'],
      ]) {
        err.clear();
        expect(run(arguments, _checkout()), 64, reason: '$arguments');
        expect(
          err.toString(),
          contains('Usage: dart run tool/release_version.dart'),
        );
      }
    });
  });
}

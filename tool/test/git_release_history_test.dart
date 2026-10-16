@Tags(['process'])
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xp_tool/xp_tool.dart';

/// A throwaway git repository with a history built by [commit] and [tag].
class _Repo {
  new() : root = Directory.systemTemp.createTempSync('xp_release_git_') {
    git(['init', '--quiet', '--initial-branch=main']);
    git(['config', 'user.email', 'test@example.com']);
    git(['config', 'user.name', 'Test']);
    git(['config', 'commit.gpgsign', 'false']);
    git(['config', 'tag.gpgsign', 'false']);
  }

  final Directory root;
  var _files = 0;

  String git(List<String> arguments) {
    final result = Process.runSync(
      'git',
      arguments,
      workingDirectory: root.path,
    );
    if (result.exitCode != 0) fail('git $arguments: ${result.stderr}');
    return '${result.stdout}'.trim();
  }

  void commit(String message) {
    File(p.join(root.path, 'file${_files++}')).writeAsStringSync('x');
    git(['add', '.']);
    git(['commit', '--quiet', '-m', message]);
  }

  void tag(String name) => git(['tag', name]);
}

_Repo _repo() {
  final repo = _Repo();
  addTearDown(() => repo.root.deleteSync(recursive: true));
  return repo;
}

void main() {
  test('reads tags, messages and the commit count from git', () {
    final repo = _repo()
      ..commit('chore: start')
      ..tag('v0.1.0')
      ..commit('fix: one\n\nThe body.')
      ..tag('not-a-release')
      ..commit('feat: two');
    final history = GitReleaseHistory(repo.root.path);

    expect(history.tagsAtHead(), isEmpty);
    expect(history.mergedTags(), ['v0.1.0']);
    expect(history.messagesSince('v0.1.0'), [
      'feat: two',
      'fix: one\n\nThe body.',
    ]);
    expect(history.headMessage(), 'feat: two');
    expect(history.commitCount(), 3);

    repo.tag('v0.2.0');
    expect(history.tagsAtHead(), ['v0.2.0']);
  });

  test('follows the first parent of a merge commit', () {
    final repo = _repo()
      ..commit('chore: start')
      ..tag('v0.1.0')
      ..git(['checkout', '--quiet', '-b', 'topic'])
      ..commit('feat: on the branch')
      ..commit('fix: on the branch')
      ..git(['checkout', '--quiet', 'main'])
      ..git([
        'merge',
        '--quiet',
        '--no-ff',
        'topic',
        '-m',
        'Merge pull request #2 from a/topic',
        '-m',
        'fix: the title',
      ]);
    final history = GitReleaseHistory(repo.root.path);

    expect(history.messagesSince('v0.1.0'), [
      'Merge pull request #2 from a/topic\n\nfix: the title',
    ]);
    final plan = planRelease(
      history: history,
      pubspecVersion: const ReleaseVersion(0, 0, 1),
    );
    expect(plan.version, '0.1.1');
    expect(plan.build, 4);
  });

  test('a shallow clone has no build number', () {
    final repo = _repo()
      ..commit('chore: one')
      ..commit('chore: two');
    final clone = Directory.systemTemp.createTempSync('xp_release_shallow_');
    addTearDown(() => clone.deleteSync(recursive: true));
    final result = Process.runSync('git', [
      'clone',
      '--quiet',
      '--depth=1',
      'file://${repo.root.path}',
      clone.path,
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');

    expect(
      () => GitReleaseHistory(clone.path).commitCount(),
      throwsA(
        isA<ProcessException>().having(
          (e) => e.message,
          'message',
          contains('fetch-depth: 0'),
        ),
      ),
    );
  });

  test('a git failure is a ProcessException', () {
    final repo = _repo()..commit('chore: one');
    expect(
      () => GitReleaseHistory(repo.root.path).messagesSince('v9.9.9'),
      throwsA(isA<ProcessException>()),
    );
  });

  group('runReleaseVersion next', () {
    test('reads the history of the repository at root', () {
      final repo = _repo();
      File(p.join(repo.root.path, 'apps/xpd/pubspec.yaml'))
        ..createSync(recursive: true)
        ..writeAsStringSync('name: xpd\nversion: 0.0.1\n');
      repo.commit('feat: the first release');
      final out = StringBuffer();

      final code = runReleaseVersion(
        ['next'],
        root: repo.root,
        out: out,
        err: StringBuffer(),
      );

      expect(code, 0);
      expect('$out', 'version=0.1.0\ntag=v0.1.0\nbuild=1\nprerelease=true\n');
    });

    test('fails when git does', () {
      final root = Directory.systemTemp.createTempSync('xp_release_nogit_');
      addTearDown(() => root.deleteSync(recursive: true));
      File(p.join(root.path, 'apps/xpd/pubspec.yaml'))
        ..createSync(recursive: true)
        ..writeAsStringSync('name: xpd\nversion: 0.0.1\n');
      final err = StringBuffer();

      final code = runReleaseVersion(
        ['next'],
        root: root,
        out: StringBuffer(),
        err: err,
      );

      expect(code, 1);
      expect('$err', startsWith('release_version: ProcessException'));
    });
  });
}

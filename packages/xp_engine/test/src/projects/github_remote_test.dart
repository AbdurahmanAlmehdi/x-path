import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  group('GitHubRemote.parse', () {
    const expected = GitHubRemote(owner: 'octo-org', name: 'app.v2');

    test('reads every spelling of a GitHub repository', () {
      for (final text in [
        'octo-org/app.v2',
        'octo-org/app.v2.git',
        'github.com/octo-org/app.v2',
        'https://github.com/octo-org/app.v2',
        'https://github.com/octo-org/app.v2.git',
        'https://github.com/octo-org/app.v2/',
        'http://github.com/octo-org/app.v2',
        'https://x-access-token@github.com/octo-org/app.v2.git',
        'git@github.com:octo-org/app.v2.git',
        'git@github.com:octo-org/app.v2',
        'ssh://git@github.com/octo-org/app.v2.git',
        'git://github.com/octo-org/app.v2.git',
        '  https://GitHub.com/octo-org/app.v2.git\n',
      ]) {
        expect(GitHubRemote.parse(text), expected, reason: text);
      }
    });

    test('knows the full name', () {
      expect(expected.fullName, 'octo-org/app.v2');
    });

    test('rejects other hosts and things that are not repositories', () {
      for (final text in [
        '',
        'octo-org',
        'https://gitlab.com/octo-org/app',
        'git@bitbucket.org:octo-org/app.git',
        'https://github.com/octo-org',
        'https://github.com/octo-org/app/tree/main',
        'a/b/c',
        '../app',
        'owner/..',
        './app',
        'owner name/app',
      ]) {
        expect(GitHubRemote.parse(text), isNull, reason: text);
      }
    });

    test('compares by value', () {
      expect(GitHubRemote.parse('a/b'), GitHubRemote.parse('a/b.git'));
    });
  });
}

import 'package:test/test.dart';
import 'package:xp_api/xp_api.dart';

void main() {
  group('GitRemote.parse', () {
    test('reads scp-like, ssh:// and file:// URLs', () {
      expect(
        GitRemote.parse('git@bitbucket.org:ws/app.git'),
        const GitRemote(host: 'bitbucket.org', path: 'ws/app'),
      );
      expect(
        GitRemote.parse('ssh://git@gitlab.com:2222/group/sub/app.git/'),
        const GitRemote(host: 'gitlab.com', path: 'group/sub/app', port: 2222),
      );
      expect(
        GitRemote.parse('  file:///srv/git/app.git '),
        const GitRemote(host: Project.localHost, path: 'srv/git/app'),
      );
    });

    test('keeps more than two segments for a GitLab subgroup', () {
      expect(
        GitRemote.parse('git@gitlab.com:group/sub/app.git')?.path,
        'group/sub/app',
      );
    });

    test('is null for anything that is not SSH or file://', () {
      for (final text in [
        'https://bitbucket.org/ws/app.git',
        'http://host/app',
        '/srv/git/app.git',
        'octo/app',
        'git@host:',
        'git@host:../app',
        'ssh:///no-host',
        'file://relative',
        '',
      ]) {
        expect(GitRemote.parse(text), isNull, reason: text);
      }
    });
  });

  group('normalised', () {
    test('is the same text for every spelling of one repository', () {
      final spellings = {
        for (final text in [
          'git@bitbucket.org:ws/app.git',
          'git@Bitbucket.ORG:ws/app',
          'ssh://git@bitbucket.org/ws/app.git',
          'ssh://bitbucket.org:22/ws/app/',
          'ssh://other@bitbucket.org/ws/app',
          GitRemote.sshUrlFor('https://user@bitbucket.org/ws/app.git')!,
        ])
          GitRemote.parse(text)?.normalised,
      };

      expect(spellings, {'ssh://bitbucket.org/ws/app'});
    });

    test('keeps a port that is not 22, and a local folder', () {
      expect(
        GitRemote.parse('ssh://h.example:2222/a/b')?.normalised,
        'ssh://h.example:2222/a/b',
      );
      expect(GitRemote.parse('file:///srv/a.git')?.normalised, 'file:///srv/a');
    });
  });

  group('GitRemote.sshUrlFor', () {
    test('derives the SSH URL of an HTTPS URL', () {
      expect(
        GitRemote.sshUrlFor('https://bitbucket.org/ws/app.git'),
        'git@bitbucket.org:ws/app.git',
      );
      expect(
        GitRemote.sshUrlFor('https://me@Bitbucket.org/ws/app'),
        'git@bitbucket.org:ws/app.git',
      );
      expect(
        GitRemote.sshUrlFor('http://gitlab.example/group/sub/app/'),
        'git@gitlab.example:group/sub/app.git',
      );
    });

    test('is null for anything that is not an HTTPS URL with a path', () {
      for (final text in [
        'git@bitbucket.org:ws/app.git',
        'https://bitbucket.org',
        'https://bitbucket.org/',
        'file:///srv/app.git',
        'nope',
      ]) {
        expect(GitRemote.sshUrlFor(text), isNull, reason: text);
      }
    });
  });
}

import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

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
        const GitRemote(host: GitRemote.localHost, path: 'srv/git/app'),
      );
    });

    test('keeps more than two segments for a GitLab subgroup', () {
      final remote = GitRemote.parse('git@gitlab.com:group/sub/app.git')!;

      expect(remote.fullName, 'group/sub/app');
      expect(remote.isLocal, isFalse);
      expect(GitRemote.parse('file:///srv/app')!.isLocal, isTrue);
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

  group('sourceKey', () {
    test('is the same for every spelling of one repository', () {
      final keys = {
        for (final text in [
          'git@bitbucket.org:ws/app.git',
          'git@Bitbucket.ORG:ws/app',
          'ssh://git@bitbucket.org/ws/app.git',
          'ssh://bitbucket.org:22/ws/app/',
          'ssh://other@bitbucket.org/ws/app',
          GitRemote.sshUrlFor('https://user@bitbucket.org/ws/app.git')!,
        ])
          GitRemote.parse(text)!.sourceKey,
      };

      expect(keys, hasLength(1));
      expect(keys.single, matches(RegExp(r'^h[0-9a-f]{16}$')));
      expect(keys.single, matches(GitMirror.keyPattern));
    });

    test('differs for another repository, host or port', () {
      String key(String text) => GitRemote.parse(text)!.sourceKey;

      final app = key('git@bitbucket.org:ws/app.git');
      expect(key('git@bitbucket.org:ws/other.git'), isNot(app));
      expect(key('git@gitlab.com:ws/app.git'), isNot(app));
      expect(key('ssh://git@bitbucket.org:2222/ws/app.git'), isNot(app));
      expect(key('file:///ws/app.git'), isNot(app));
    });

    test('is the SHA-256 of the normalised remote', () {
      final remote = GitRemote.parse('git@bitbucket.org:ws/app.git')!;

      expect(remote.normalised, 'ssh://bitbucket.org/ws/app');
      expect(
        GitRemote.parse('ssh://h.example:2222/a/b')!.normalised,
        'ssh://h.example:2222/a/b',
      );
      expect(GitRemote.parse('file:///srv/a.git')!.normalised, 'file:///srv/a');
      // printf 'ssh://bitbucket.org/ws/app' | shasum -a 256
      expect(remote.sourceKey, 'h212353d06bc50c7b');
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

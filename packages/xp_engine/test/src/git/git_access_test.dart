import 'package:test/test.dart';
import 'package:xp_engine/xp_engine.dart';

void main() {
  final sha = 'c' * 40;

  String? explain(
    String output,
    String url, {
    GitAccessReader reader = GitAccessReader.runner,
    String? sha,
  }) => explainGitAccess(output, url: url, reader: reader, sha: sha);

  group('explainGitAccess', () {
    test('says how to replace a host key that changed', () {
      for (final output in [
        'Host key verification failed.',
        '@ WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED! @',
      ]) {
        expect(
          explain(output, 'git@bitbucket.org:ws/app.git'),
          'The host key of bitbucket.org is not the one SSH on this machine '
          'recorded for it. If bitbucket.org changed its key, remove the old '
          'one (ssh-keygen -R bitbucket.org) as the user of this runner and '
          'run "ssh -T git@bitbucket.org" once to check the new one, then '
          'run the job again.',
          reason: output,
        );
      }
    });

    test('speaks of no host key for a local repository, which has none', () {
      for (final url in ['file:///srv/git/app.git', '/srv/git/app.git']) {
        expect(
          explain('Host key verification failed.', url),
          isNull,
          reason: url,
        );
      }
    });

    test('says which host has no commit, for every way git says so', () {
      for (final output in [
        'fatal: remote error: upload-pack: not our ref $sha',
        "fatal: couldn't find remote ref $sha",
        'error: Server does not allow request for unadvertised object $sha',
        'fatal: no such remote ref $sha',
      ]) {
        expect(
          explain(output, 'git@github.com:octo/app.git', sha: sha),
          'GitHub has no commit cccccccccccc to give (octo/app). It was not '
          'pushed or is not reachable from a branch. Push it, then run the '
          'job again.',
          reason: output,
        );
      }
      const missing = 'fatal: no such remote ref x';
      expect(
        explain(missing, 'git@gitlab.com:group/sub/app.git', sha: sha),
        startsWith(
          'gitlab.com has no commit cccccccccccc to give '
          '(group/sub/app).',
        ),
      );
      expect(
        explain(missing, 'file:///srv/git/app.git', sha: sha),
        startsWith(
          'The repository has no commit cccccccccccc to give '
          '(srv/git/app).',
        ),
      );
      expect(
        explain(missing, '/srv/git/app.git', sha: sha),
        startsWith(
          'The repository has no commit cccccccccccc to give '
          '(/srv/git/app.git).',
        ),
      );
    });

    test('does not speak of a commit when none was asked for', () {
      expect(
        explain('fatal: no such remote ref x', 'git@gitlab.com:g/app.git'),
        isNull,
      );
    });

    test('says where each host takes the key it refused', () {
      const denied = 'git@host: Permission denied (publickey).';
      expect(
        explain(denied, 'git@github.com:octo/app.git'),
        "This runner cannot read octo/app over SSH. Fix: add this runner's "
        'SSH key as a deploy key on octo/app (GitHub: Settings, Deploy keys), '
        'or use the key of a user who can read it, then run the job again.',
      );
      expect(
        explain(
          denied,
          'git@bitbucket.org:ws/app.git',
          reader: GitAccessReader.engine,
        ),
        "The engine cannot read ws/app over SSH. Fix: add the engine's SSH "
        'key (~/.ssh/id_ed25519.pub of the user the engine runs as, with no '
        'passphrase) as an access key of ws/app (Bitbucket: Repository '
        'settings, Access keys), then add the project again.',
      );
      expect(
        explain(
          'ERROR: Repository not found.',
          'ssh://git@git.example.com:2222/team/app.git',
        ),
        "This runner cannot read team/app over SSH. Fix: add this runner's "
        'SSH key to git.example.com with read access to team/app, then run '
        'the job again.',
      );
    });

    test('asks a local repository to be readable, not a key', () {
      for (final output in [
        "fatal: '/srv/git/app.git' does not appear to be a git repository",
        'fatal: Could not read from remote repository.',
      ]) {
        expect(
          explain(output, 'file:///srv/git/app.git'),
          'This runner cannot read srv/git/app. Fix: let the user of this '
          'runner read the repository, then run the job again.',
          reason: output,
        );
      }
      expect(
        explain('remote: Access denied', '/srv/git/app.git'),
        'This runner cannot read /srv/git/app.git. Fix: let the user of '
        'this runner read the repository, then run the job again.',
      );
      expect(
        explain('remote: HTTP Basic: Authentication failed', 'x'),
        contains('let the user of this runner read the repository'),
      );
    });

    test('leaves output it does not know to the caller', () {
      expect(
        explain(
          'ssh: Could not resolve hostname nowhere',
          'git@nowhere:app.git',
        ),
        isNull,
      );
    });
  });
}

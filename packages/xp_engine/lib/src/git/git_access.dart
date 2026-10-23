import 'package:xp_engine/src/projects/git_remote.dart';
import 'package:xp_engine/src/projects/github_remote.dart';

/// Who reached for a repository over SSH, for the words of
/// [explainGitAccess].
enum GitAccessReader {
  /// A runner fetching the commit of a job (ADR 0009).
  runner(
    name: 'this runner',
    key: "this runner's SSH key",
    user: 'the user of this runner',
    retry: 'run the job again',
  ),

  /// The engine adding a project (ADR 0015). The LaunchAgent and the Docker
  /// image have no terminal, so its key must need no passphrase.
  engine(
    name: 'the engine',
    key:
        "the engine's SSH key (~/.ssh/id_ed25519.pub of the user the engine "
        'runs as, with no passphrase)',
    user: 'the user the engine runs as',
    retry: 'add the project again',
  );

  new({
    required this.name,
    required this.key,
    required this.user,
    required this.retry,
  });

  /// Who reads, in a sentence: `this runner`.
  final String name;

  /// The key it reads with.
  final String key;

  /// The account it runs as.
  final String user;

  /// What to do once it is fixed.
  final String retry;
}

/// What went wrong when git could not read [url], and what to do about it on
/// the host of [url], from git's [output]: a key the host does not take, a
/// host key that changed, or a commit [sha] the host does not have. `null`
/// for output it does not recognise.
///
/// SSH runs with `StrictHostKeyChecking=accept-new`, so a host key it has not
/// seen is recorded, and a host key failure means the key changed (Q6).
String? explainGitAccess(
  String output, {
  required String url,
  required GitAccessReader reader,
  String? sha,
}) {
  final text = output.toLowerCase();
  final github = GitHubRemote.parse(url);
  final remote = GitRemote.parse(url);
  final host = github != null ? 'github.com' : remote?.host;
  // The SSH host, if there is one: not for a local repository.
  final sshHost = host == GitRemote.localHost ? null : host;
  final repo = github?.fullName ?? remote?.fullName ?? url;
  final retry = reader.retry;
  if (text.contains('host key verification failed') ||
      text.contains('remote host identification has changed')) {
    if (sshHost == null) {
      return 'The host key of the repository server is not the one SSH on '
          'this machine recorded for it. If the server changed its key, '
          'remove the old one with ssh-keygen -R as ${reader.user}, then '
          '$retry.';
    }
    return 'The host key of $sshHost is not the one SSH on this machine '
        'recorded for it. If $sshHost changed its key, remove the old one '
        '(ssh-keygen -R $sshHost) as ${reader.user} and run '
        '"ssh -T git@$sshHost" once to check the new one, then $retry.';
  }
  if (sha != null &&
      (text.contains('not our ref') ||
          text.contains("couldn't find remote ref") ||
          text.contains('unadvertised object') ||
          text.contains('no such remote ref'))) {
    final server = switch (host) {
      'github.com' => 'GitHub',
      null || GitRemote.localHost => 'The repository',
      final host => host,
    };
    return '$server has no commit ${sha.substring(0, 12)} to give '
        '($repo). It was not pushed or is not reachable from a branch. '
        'Push it, then $retry.';
  }
  if (text.contains('permission denied') ||
      text.contains('could not read from remote repository') ||
      text.contains('repository not found') ||
      text.contains('does not appear to be a git repository') ||
      text.contains('access denied') ||
      text.contains('authentication failed')) {
    final key = reader.key;
    final fix = switch (host) {
      'github.com' =>
        'add $key as a deploy key on $repo (GitHub: Settings, Deploy keys), '
            'or use the key of a user who can read it',
      'bitbucket.org' =>
        'add $key as an access key of $repo '
            '(Bitbucket: Repository settings, Access keys)',
      null || GitRemote.localHost => 'let ${reader.user} read the repository',
      final host => 'add $key to $host with read access to $repo',
    };
    final name = reader.name;
    return '${name[0].toUpperCase()}${name.substring(1)} cannot read $repo'
        '${sshHost == null ? '' : ' over SSH'}. Fix: $fix, then $retry.';
  }
  return null;
}

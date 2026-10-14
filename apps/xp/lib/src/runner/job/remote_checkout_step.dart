import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xp_api/xp_api.dart';
import 'package:xp_engine/xp_engine.dart';

final _fullSha = RegExp(r'^[0-9a-f]{40}$');

/// What the offer of the engine says about the source of a leased job: the
/// repository and the exact commit, never a credential (ADR 0009).
class LeaseSource {
  /// Creates the source.
  const new({this.repository, this.sha});

  /// The source of the job offered in [offer].
  factory of(LeaseOfferFrame offer) =>
      LeaseSource(repository: offer.repository, sha: offer.sha);

  /// Where to fetch from, or `null` if the engine did not say.
  final LeaseRepository? repository;

  /// The commit to build, or `null` if the engine named none.
  final String? sha;
}

/// `git.checkout` on a runner (ADR 0009): the source comes from GitHub over
/// the runner's own SSH access, not from the engine's mirror.
///
/// The runner keeps a bare cache per repository, keyed by the GitHub
/// repository id. The step fetches the exact commit of the offer into it (with
/// `GIT_SSH_COMMAND` set to `ssh -o BatchMode=yes`, so that git never asks
/// for a password or a passphrase), cuts a fresh worktree at that commit and
/// verifies that its `HEAD` is the commit before the job goes on. When the
/// runner cannot read the repository, the job fails with what to do: add the
/// runner's SSH key as a deploy key on the repository.
///
/// Every git command goes through the job's process runner, so its output is
/// in the log of the step and a cancel stops it with its process group.
class RemoteCheckoutStep extends Step<GitCheckoutInput, GitCheckoutResult> {
  /// Creates the step for a job whose offer said `source`.
  ///
  /// `testUrl` replaces the URL of the repository: for end-to-end tests that
  /// fetch from a local repository; real runners never set it. `queues`
  /// serialises the work on one repository, because jobs share its cache.
  const new({required this._source, required this._queues, this._testUrl});

  final LeaseSource _source;
  final SerialQueues _queues;
  final String? _testUrl;

  /// The environment of every git command: no configuration of the machine,
  /// no prompt, messages in English.
  static const _environment = {
    'GIT_CONFIG_NOSYSTEM': '1',
    'GIT_CONFIG_GLOBAL': '/dev/null',
    'GIT_TERMINAL_PROMPT': '0',
    'LC_ALL': 'C',
  };

  /// `ssh` never prompts (`BatchMode`), whatever the key needs.
  static const sshCommand = 'ssh -o BatchMode=yes -o ConnectTimeout=30';

  @override
  String get kind => 'git.checkout';

  @override
  bool sideEffectOf(GitCheckoutInput input) => false;

  @override
  GitCheckoutInput decodeInput(Map<String, dynamic> json) =>
      GitCheckoutInput.fromJson(json);

  @override
  Map<String, dynamic> encodeInput(GitCheckoutInput input) => input.toJson();

  @override
  Map<String, dynamic> encodeResult(GitCheckoutResult result) => {
    'path': result.path,
    'sha': result.sha,
  };

  @override
  Future<StepOutcome<GitCheckoutResult>> run(
    GitCheckoutInput input,
    StepContext context,
  ) async {
    final repository = _source.repository;
    if (repository == null) {
      return const StepFailed(
        'The engine named no repository for this job, so the runner cannot '
        'get its source.',
      );
    }
    final sha = _source.sha;
    if (sha == null || !_fullSha.hasMatch(sha)) {
      return StepFailed(
        sha == null
            ? 'The engine named no commit for this job. It starts from a job '
                  'that made no version commit.'
            : 'The engine named "$sha", which is not a full commit id.',
      );
    }
    return await _queues.run(
      'repository-${repository.githubRepoId}',
      () => _checkout(
        input.worktree,
        _testUrl ?? repository.sshUrl,
        sha,
        context,
      ),
    );
  }

  Future<StepOutcome<GitCheckoutResult>> _checkout(
    ReleaseWorktree target,
    String url,
    String sha,
    StepContext context,
  ) async {
    final mirror = target.mirror.path;
    final source = p.dirname(p.dirname(mirror));
    Directory(p.dirname(mirror)).createSync(recursive: true);

    // The cache: a bare repository that has the commit, from the earlier job
    // or fetched now.
    if (!File(p.join(mirror, 'HEAD')).existsSync()) {
      final init = await _git(context, source, [
        '-c',
        'init.defaultBranch=main',
        'init',
        '--bare',
        '--quiet',
        mirror,
      ]);
      if (!init.exit.succeeded) return _failed('create the cache', init);
    }
    final configure = await _git(context, mirror, [
      'config',
      'remote.origin.url',
      url,
    ]);
    if (!configure.exit.succeeded) return _failed('set the origin', configure);
    final has = await _git(context, mirror, [
      'cat-file',
      '-e',
      '$sha^{commit}',
    ]);
    if (has.exit.cancelled) return _cancelled;
    if (!has.exit.succeeded) {
      final fetch = await _git(context, mirror, [
        'fetch',
        '--no-tags',
        'origin',
        sha,
      ], network: true);
      if (fetch.exit.cancelled) return _cancelled;
      if (!fetch.exit.succeeded) return StepFailed(_explain(fetch, url, sha));
    }
    // Keep the commit reachable, so that a cleanup of the cache keeps it.
    await _git(context, mirror, ['update-ref', 'refs/xpath/$sha', sha]);

    // A fresh worktree: an old one of the same job is thrown away.
    await _git(context, mirror, ['worktree', 'prune']);
    final old = Directory(target.path);
    if (old.existsSync()) old.deleteSync(recursive: true);
    await _git(context, mirror, ['worktree', 'prune']);
    Directory(p.dirname(target.path)).createSync(recursive: true);
    final add = await _git(context, mirror, [
      'worktree',
      'add',
      '--detach',
      target.path,
      sha,
    ]);
    if (add.exit.cancelled) return _cancelled;
    if (!add.exit.succeeded) return _failed('check out $sha', add);

    // Never run anything on a tree that is not the commit the engine named.
    final head = await _git(context, target.path, ['rev-parse', 'HEAD']);
    if (head.exit.cancelled) return _cancelled;
    final actual = head.stdout.trim();
    if (!head.exit.succeeded || actual != sha) {
      return StepFailed(
        'The worktree is at ${actual.isEmpty ? 'an unknown commit' : actual}, '
        'not at $sha, the commit the engine named. The job does not run on '
        'any other source.',
      );
    }
    return StepSucceeded(GitCheckoutResult(path: target.path, sha: sha));
  }

  static const _cancelled = StepFailed('The checkout was cancelled.');

  Future<_GitRun> _git(
    StepContext context,
    String directory,
    List<String> arguments, {
    bool network = false,
  }) async {
    final lines = <String>[];
    final stdout = <String>[];
    final exit = await context.run(
      ProcessCommand(
        'git',
        arguments: arguments,
        workingDirectory: directory,
        environment: {
          ..._environment,
          if (network) 'GIT_SSH_COMMAND': sshCommand,
        },
        passThroughEnvironment: const ['SSH_AUTH_SOCK'],
      ),
      onLine: (line) {
        lines.add(line.text);
        if (line.stream == LogStream.stdout) stdout.add(line.text);
      },
    );
    return _GitRun(exit, lines, stdout.join('\n'));
  }

  StepFailed _failed(String what, _GitRun run) => StepFailed(
    'git could not $what (exit code ${run.exit.exitCode})'
    '${run.lines.isEmpty ? '' : ': ${run.lines.last}'}.',
  );

  /// The message for a fetch that failed: what is wrong and what to do.
  String _explain(_GitRun run, String url, String sha) {
    final text = run.lines.join('\n').toLowerCase();
    final repo = GitHubRemote.parse(url)?.fullName ?? url;
    if (text.contains('host key verification failed')) {
      return 'SSH on this machine does not trust the host key of the '
          'repository server. Fix: run "ssh -T git@github.com" once as the '
          'user of this runner and accept the key, then run the job again.';
    }
    if (text.contains('not our ref') ||
        text.contains("couldn't find remote ref") ||
        text.contains('unadvertised object') ||
        text.contains('no such remote ref')) {
      return 'GitHub has no commit ${sha.substring(0, 12)} to give '
          '($repo). It was not pushed or is not reachable from a branch. '
          'Push it, then run the job again.';
    }
    if (text.contains('permission denied') ||
        text.contains('could not read from remote repository') ||
        text.contains('repository not found') ||
        text.contains('access denied') ||
        text.contains('authentication failed')) {
      return 'This runner cannot read $repo over SSH. Fix: '
          "add this runner's SSH key as a deploy key on $repo "
          '(GitHub: Settings, Deploy keys), or use the key of a user who can '
          'read it, then run the job again.';
    }
    return 'git fetch failed (exit code ${run.exit.exitCode})'
        '${run.lines.isEmpty ? '' : ': ${run.lines.last}'}. Check that this '
        'runner can reach $repo over SSH.';
  }
}

class _GitRun {
  const new(this.exit, this.lines, this.stdout);

  final ProcessExit exit;
  final List<String> lines;
  final String stdout;
}

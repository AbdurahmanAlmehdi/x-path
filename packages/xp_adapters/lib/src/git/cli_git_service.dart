import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xp_adapters/src/git/git_identity.dart';
import 'package:xp_engine/xp_engine.dart';

/// A [GitService] over the `git` command line.
///
/// Layout under the data directory: the mirror of GitHub repository `N` is
/// `mirrors/N.git`, the worktree `W` of that mirror is `worktrees/N/W`.
///
/// Every command runs with the system and global git configuration switched
/// off, so nothing in the owner's `~/.gitconfig` (signing, hooks, URL
/// rewrites, credential helpers) changes what XPath does, and with terminal
/// prompts disabled, so a missing credential fails instead of hanging.
///
/// The GitHub token (`github.token` in the [SecretStore]) reaches git only for
/// `https://github.com` and only through the environment: the credential
/// helper is a shell snippet that reads `XPATH_GIT_TOKEN`, so the token is in
/// no argument, no URL and no config file.
class CliGitService implements GitService {
  /// Creates the service.
  ///
  /// [timeout] bounds each git command; a command that takes longer is killed.
  new({
    required this._runner,
    required this._secrets,
    required this._dataDir,
    this.identity = GitIdentity.xpath,
    this.gitExecutable = 'git',
    this.timeout = const Duration(minutes: 10),
  });

  /// The author and committer of tags.
  final GitIdentity identity;

  /// The program to run.
  final String gitExecutable;

  /// How long one git command may take.
  final Duration timeout;

  final ProcessRunner _runner;
  final SecretStore _secrets;
  final String _dataDir;

  static const _tokenVariable = 'XPATH_GIT_TOKEN';

  // Answers git's `get` request for credentials with the token in the
  // environment; ignores `store` and `erase`.
  static const _credentialHelper =
      r'!f() { test "$1" = get || exit 0; '
      r'echo username=x-access-token; echo "password=$XPATH_GIT_TOKEN"; }; f';

  static final _fullSha = RegExp(r'^[0-9a-f]{40}$');
  static final _abbreviatedSha = RegExp(r'^[0-9a-fA-F]{4,40}$');
  static final _worktreeName = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');
  // `src:dst`, both full refs. A leading `+` (force) cannot match; a `+` inside
  // a name is fine, tags look like `v1.2.3+45`.
  static final _refspec = RegExp(
    r'^refs/[^\s:*?\[\\^~\x00-\x1f\x7f]+:refs/[^\s:*?\[\\^~\x00-\x1f\x7f]+$',
  );

  String get _mirrorsDir => p.join(_dataDir, 'mirrors');

  @override
  Future<GitMirror> ensureMirror({
    required int githubRepoId,
    required String remoteUrl,
  }) async {
    if (remoteUrl.isEmpty || remoteUrl.startsWith('-')) {
      throw ArgumentError.value(remoteUrl, 'remoteUrl', 'is not a URL');
    }
    final path = p.join(_mirrorsDir, '$githubRepoId.git');
    final mirror = GitMirror(githubRepoId: githubRepoId, path: path);
    if (!File(p.join(path, 'HEAD')).existsSync()) {
      Directory(_mirrorsDir).createSync(recursive: true);
      await _ok('init', [
        '-c',
        'init.defaultBranch=main',
        'init',
        '--bare',
        '--quiet',
        path,
      ], cwd: _mirrorsDir);
    }
    final current = await _git(['remote', 'get-url', 'origin'], cwd: path);
    if (current.exitCode != 0) {
      await _ok('remote', ['remote', 'add', 'origin', remoteUrl], cwd: path);
    } else if (current.stdout.trim() != remoteUrl) {
      await _ok('remote', [
        'remote',
        'set-url',
        'origin',
        remoteUrl,
      ], cwd: path);
    }
    return mirror;
  }

  /// Fetches `refs/heads/*` into `refs/remotes/origin/*` and `refs/tags/*` into
  /// itself, both forced and pruned, so the mirror shows what the remote has.
  ///
  /// A tag created in the mirror and not pushed yet is pruned by the next
  /// fetch; creating it again on the same commit is a no-op for the caller.
  @override
  Future<void> fetch(GitMirror mirror) => _ok(
    'fetch',
    [
      'fetch',
      '--prune',
      '--no-tags',
      'origin',
      '+refs/heads/*:refs/remotes/origin/*',
      '+refs/tags/*:refs/tags/*',
    ],
    cwd: mirror.path,
    network: true,
  );

  @override
  Future<String> resolveRef(GitMirror mirror, String ref) async {
    final candidates = [
      if (_fullSha.hasMatch(ref)) ref,
      'refs/heads/$ref',
      'refs/remotes/origin/$ref',
      'refs/tags/$ref',
      if (!_fullSha.hasMatch(ref) && _abbreviatedSha.hasMatch(ref)) ref,
    ];
    for (final candidate in candidates) {
      final sha = await _commitOf(mirror, candidate);
      if (sha != null) return sha;
    }
    throw GitRefNotFoundException(ref);
  }

  @override
  Future<GitWorktree> createWorktree(
    GitMirror mirror, {
    required String name,
    required String sha,
  }) async {
    if (!_worktreeName.hasMatch(name)) {
      throw ArgumentError.value(name, 'name', 'is not a safe directory name');
    }
    final full = await resolveRef(mirror, sha);
    final path = p.join(_dataDir, 'worktrees', '${mirror.githubRepoId}', name);
    await _discardWorktree(mirror, path);
    Directory(p.dirname(path)).createSync(recursive: true);
    await _ok('worktree', [
      'worktree',
      'add',
      '--detach',
      path,
      full,
    ], cwd: mirror.path);
    return GitWorktree(mirror: mirror, path: path, sha: full);
  }

  @override
  Future<void> removeWorktree(GitWorktree worktree) =>
      _discardWorktree(worktree.mirror, worktree.path);

  @override
  Future<TagOutcome> createTag(
    GitMirror mirror, {
    required String name,
    required String sha,
    required String message,
  }) async {
    await _checkRefName('refs/tags/$name', name);
    if (message.trim().isEmpty) {
      throw ArgumentError.value(message, 'message', 'is blank');
    }
    final full = await resolveRef(mirror, sha);
    final existing = await _commitOf(mirror, 'refs/tags/$name');
    if (existing != null) {
      if (existing == full) return TagOutcome.reused;
      throw GitTagConflictException(
        tag: name,
        existingSha: existing,
        requestedSha: full,
      );
    }
    await _ok('tag', [
      'tag',
      '-a',
      '-m',
      message,
      name,
      full,
    ], cwd: mirror.path);
    return TagOutcome.created;
  }

  @override
  Future<BranchOutcome> upsertBranch(
    GitMirror mirror, {
    required String name,
    required String sha,
  }) async {
    await _checkRefName('refs/heads/$name', name);
    final full = await resolveRef(mirror, sha);
    final local = await _commitOf(mirror, 'refs/heads/$name');
    if (local == full) return BranchOutcome.unchanged;
    final tip = local ?? await _commitOf(mirror, 'refs/remotes/origin/$name');
    if (tip != null && !await _isAncestor(mirror, tip, full)) {
      throw GitBranchConflictException(
        branch: name,
        currentSha: tip,
        requestedSha: full,
      );
    }
    // The old value makes the update atomic: an empty one means "must not
    // exist yet".
    await _ok('update-ref', [
      'update-ref',
      'refs/heads/$name',
      full,
      local ?? '',
    ], cwd: mirror.path);
    return local == null ? BranchOutcome.created : BranchOutcome.updated;
  }

  @override
  Future<void> push(GitMirror mirror, {required List<String> refspecs}) async {
    if (refspecs.isEmpty) {
      throw ArgumentError.value(refspecs, 'refspecs', 'is empty');
    }
    for (final refspec in refspecs) {
      if (!_refspec.hasMatch(refspec)) {
        throw ArgumentError.value(
          refspec,
          'refspecs',
          'is not a plain refs/...:refs/... refspec',
        );
      }
    }
    final output = await _git(
      ['push', 'origin', ...refspecs],
      cwd: mirror.path,
      network: true,
    );
    if (output.exitCode == 0) return;
    final stderr = output.stderr.trim();
    final rejected =
        stderr.contains('rejected') ||
        stderr.contains('non-fast-forward') ||
        stderr.contains('already exists');
    final message = 'git push failed (exit ${output.exitCode}): $stderr';
    throw rejected ? GitPushRejectedException(message) : GitException(message);
  }

  /// Forgets the worktree at [path] and deletes its directory, whatever state
  /// it is in.
  Future<void> _discardWorktree(GitMirror mirror, String path) async {
    if (Directory(mirror.path).existsSync()) {
      await _git(['worktree', 'remove', '--force', path], cwd: mirror.path);
    }
    final directory = Directory(path);
    if (directory.existsSync()) directory.deleteSync(recursive: true);
    if (Directory(mirror.path).existsSync()) {
      await _git(['worktree', 'prune'], cwd: mirror.path);
    }
  }

  /// Fails with an [ArgumentError] unless [fullRef] is a valid ref and [name]
  /// cannot be mistaken for an option.
  Future<void> _checkRefName(String fullRef, String name) async {
    final valid =
        !name.startsWith('-') &&
        (await _git(['check-ref-format', fullRef])).exitCode == 0;
    if (!valid) throw ArgumentError.value(name, 'name', 'is not a valid name');
  }

  /// The commit that [ref] points at, or `null` if there is none.
  Future<String?> _commitOf(GitMirror mirror, String ref) async {
    final output = await _git([
      'rev-parse',
      '--verify',
      '--quiet',
      '$ref^{commit}',
    ], cwd: mirror.path);
    if (output.exitCode == 0) return output.stdout.trim();
    if (output.exitCode == 1) return null;
    throw _failure('rev-parse', output);
  }

  Future<bool> _isAncestor(
    GitMirror mirror,
    String ancestor,
    String descendant,
  ) async {
    final output = await _git([
      'merge-base',
      '--is-ancestor',
      ancestor,
      descendant,
    ], cwd: mirror.path);
    if (output.exitCode == 0) return true;
    if (output.exitCode == 1) return false;
    throw _failure('merge-base', output);
  }

  Future<void> _ok(
    String what,
    List<String> arguments, {
    required String cwd,
    bool network = false,
  }) async {
    final output = await _git(arguments, cwd: cwd, network: network);
    if (output.exitCode != 0) throw _failure(what, output);
  }

  GitException _failure(String what, ProcessOutput output) => GitException(
    'git $what failed (exit ${output.exitCode}): ${output.stderr.trim()}',
  );

  Future<ProcessOutput> _git(
    List<String> arguments, {
    String? cwd,
    bool network = false,
  }) async {
    final environment = {
      'GIT_CONFIG_NOSYSTEM': '1',
      'GIT_CONFIG_GLOBAL': '/dev/null',
      'GIT_TERMINAL_PROMPT': '0',
      // Git's messages are matched by text; keep them in English.
      'LC_ALL': 'C',
    };
    final config = [
      'user.name=${identity.name}',
      'user.email=${identity.email}',
    ];
    if (network) {
      final token = await _secrets.read(githubTokenSecretKey);
      if (token != null) {
        environment[_tokenVariable] = token;
        config
          ..add('credential.helper=')
          ..add('credential.https://github.com.helper=$_credentialHelper');
      }
    }
    try {
      return await _runner.run(
        gitExecutable,
        [
          for (final entry in config) ...['-c', entry],
          ...arguments,
        ],
        workingDirectory: cwd,
        environment: environment,
        timeout: timeout,
      );
    } on TimeoutException {
      throw GitException('git ${arguments.first} timed out after $timeout.');
    } on ProcessStartException catch (error) {
      throw GitException('Cannot run git: ${error.message}');
    }
  }
}
